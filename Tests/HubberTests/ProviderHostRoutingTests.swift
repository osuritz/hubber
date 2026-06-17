import Foundation
import XCTest
@testable import Hubber

final class ProviderHostRoutingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testFetchIncomingReviewsUsesSelfManagedGitLabBaseURLAndBearerToken() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.incomingMergeRequestsResponse)
        }
        let provider = try GitLabProvider(
            baseURL: XCTUnwrap(URL(string: "https://gitlab.intra.acme.com")),
            session: makeSession()
        )

        _ = try await provider.fetchIncomingReviews(
            accessToken: "gl-self-managed",
            viewerLogin: "osuritz",
            mode: .explicit
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://gitlab.intra.acme.com/api/graphql")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gl-self-managed")
    }

    func testGitLabAndGitHubRequestsKeepCredentialsIsolatedByHost() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.incomingMergeRequestsResponse)
        }
        let gitLabProvider = try GitLabProvider(
            baseURL: XCTUnwrap(URL(string: "https://gitlab.com")),
            session: makeSession()
        )

        _ = try await gitLabProvider.fetchIncomingReviews(
            accessToken: "gl-secret",
            viewerLogin: "osuritz",
            mode: .explicit
        )

        let gitLabRequest = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(gitLabRequest.url?.host, "gitlab.com")
        XCTAssertEqual(gitLabRequest.value(forHTTPHeaderField: "Authorization"), "Bearer gl-secret")
        XCTAssertNotEqual(gitLabRequest.value(forHTTPHeaderField: "Authorization"), "Bearer gh-secret")

        // GitHub Enterprise Server base-URL routing belongs to #82; GitHub still targets api.github.com here.
        MockURLProtocol.reset()
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let gitHubProvider = GitHubProvider(session: makeSession())

        _ = try await gitHubProvider.graphQL(
            query: "query Test { viewer { login } }",
            variables: [:],
            accessToken: "gh-secret"
        )

        let gitHubRequest = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(gitHubRequest.url?.host, "api.github.com")
        XCTAssertEqual(gitHubRequest.value(forHTTPHeaderField: "Authorization"), "Bearer gh-secret")
        XCTAssertNotEqual(gitHubRequest.value(forHTTPHeaderField: "Authorization"), "Bearer gl-secret")
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func response(for request: URLRequest) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return response
    }

    private static let dataResponse = Data("""
    { "data": { "ok": true } }
    """.utf8)

    private static let incomingMergeRequestsResponse = Data("""
    {
      "data": {
        "currentUser": {
          "reviewRequestedMergeRequests": {
            "nodes": [
              {
                "id": "gid://gitlab/MergeRequest/101",
                "iid": "7",
                "title": "Add GitLab incoming reviews",
                "webUrl": "https://gitlab.com/namespace/project/-/merge_requests/7",
                "createdAt": "2026-06-16T12:34:56Z",
                "draft": false,
                "project": { "fullPath": "namespace/project" },
                "author": { "username": "alice", "avatarUrl": null },
                "diffStatsSummary": { "additions": 1, "deletions": 2, "fileCount": 3 }
              }
            ]
          }
        }
      }
    }
    """.utf8)
}

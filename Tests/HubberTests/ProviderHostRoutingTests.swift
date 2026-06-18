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

        // GitHub now routes per-baseURL (#82): the default targets api.github.com; GHES routing
        // is covered by the GHES-specific tests above.
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

    func testGitHubProviderRoutesGraphQLToGHESHostWithBearerToken() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let provider = try GitHubProvider(
            baseURL: XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await provider.graphQL(
            query: "query Test { viewer { login } }",
            variables: [:],
            accessToken: "ghes-secret"
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.enterprise.acme.com/api/graphql")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghes-secret")
    }

    func testGitHubProviderDefaultStillRoutesToApiGitHubCom() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let provider = GitHubProvider(session: makeSession())

        _ = try await provider.graphQL(
            query: "query Test { viewer { login } }",
            variables: [:],
            accessToken: "gh-secret"
        )

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/graphql")
    }

    // MC-MDM-06: a github.com provider and a GHES provider in the same test each send their
    // token only to their own host — no cross-host credential leakage.
    func testGitHubDotComAndGHESProvidersKeepCredentialsIsolatedByHost() async throws {
        nonisolated(unsafe) var seen: [(host: String?, auth: String?)] = []
        MockURLProtocol.handler = { request in
            seen.append((request.url?.host, request.value(forHTTPHeaderField: "Authorization")))
            return try (Self.response(for: request), Self.dataResponse)
        }

        let dotCom = GitHubProvider(session: makeSession())
        let ghes = try GitHubProvider(
            baseURL: XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await dotCom.graphQL(query: "query { viewer { login } }", variables: [:], accessToken: "dotcom-token")
        _ = try await ghes.graphQL(query: "query { viewer { login } }", variables: [:], accessToken: "ghes-token")

        let dotComRequest = seen.first { $0.host == "api.github.com" }
        let ghesRequest = seen.first { $0.host == "github.enterprise.acme.com" }
        XCTAssertEqual(dotComRequest?.auth, "Bearer dotcom-token")
        XCTAssertEqual(ghesRequest?.auth, "Bearer ghes-token")
        // The GHES token must never reach api.github.com and vice versa.
        XCTAssertNil(seen.first { $0.host == "api.github.com" && $0.auth == "Bearer ghes-token" })
        XCTAssertNil(seen.first { $0.host == "github.enterprise.acme.com" && $0.auth == "Bearer dotcom-token" })
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

import Foundation
import XCTest
@testable import Hubber

final class GitLabProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testConformsToCodeHostProviderAndRemainingStubsReturnEmptyArrays() async throws {
        let provider: any CodeHostProvider = GitLabProvider()

        let outgoing = try await provider.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )
        let drafts = try await provider.fetchDraftPullRequests(accessToken: "tok", limit: 100)

        XCTAssertTrue(outgoing.isEmpty)
        XCTAssertTrue(drafts.isEmpty)
    }

    func testGraphQLPostsToGitLabEndpointWithBearerTokenAndReturnsData() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let data = try await provider.graphQL(
            query: "query Test { currentUser { username } }",
            variables: ["first": 1],
            accessToken: "glpat-token"
        )

        XCTAssertEqual(
            MockURLProtocol.lastRequest?.url?.absoluteString,
            "https://gitlab.com/api/graphql"
        )
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer glpat-token")
        XCTAssertEqual(data["ok"] as? Bool, true)
    }

    func testGraphQL401ThrowsBadCredentials() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request, statusCode: 401), Data())
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        do {
            _ = try await provider.graphQL(
                query: "query Test { currentUser { username } }",
                variables: [:],
                accessToken: "bad"
            )
            XCTFail("Expected badCredentials")
        } catch GitHubAuthError.badCredentials {
            // expected
        }
    }

    func testGraphQL200WithErrorsAndNoDataThrowsGitHubMessage() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.errorsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        do {
            _ = try await provider.graphQL(
                query: "query Test { currentUser { username } }",
                variables: [:],
                accessToken: "tok"
            )
            XCTFail("Expected github error")
        } catch let GitHubAuthError.github(message) {
            XCTAssertEqual(message, "x")
        }
    }

    func testFetchIncomingReviewsMapsReviewRequestedMergeRequestsAndSkipsDrafts() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.incomingMergeRequestsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let reviews = try await provider.fetchIncomingReviews(
            accessToken: "glpat-reviewer",
            viewerLogin: "osuritz",
            mode: .explicit
        )

        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://gitlab.com/api/graphql")
        XCTAssertEqual(
            MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer glpat-reviewer"
        )
        XCTAssertEqual(reviews.count, 2)

        let first = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/101" }))
        XCTAssertEqual(first.repo, "namespace/project")
        XCTAssertEqual(first.number, 7)
        XCTAssertEqual(first.title, "Add GitLab incoming reviews")
        XCTAssertEqual(first.url?.absoluteString, "https://gitlab.com/namespace/project/-/merge_requests/7")
        XCTAssertEqual(first.author.login, "alice")
        XCTAssertEqual(first.author.initials, "AL")
        XCTAssertEqual(
            first.author.avatarURL?.absoluteString,
            "https://gitlab.com/uploads/-/system/user/avatar/1/avatar.png"
        )
        XCTAssertEqual(first.sloClockStart, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-16T12:34:56Z")))
        XCTAssertEqual(first.additions, 42)
        XCTAssertEqual(first.deletions, 5)
        XCTAssertEqual(first.files, 3)

        let second = try XCTUnwrap(reviews.first(where: { $0.id == "gid://gitlab/MergeRequest/202" }))
        XCTAssertEqual(second.repo, "other/group-service")
        XCTAssertEqual(second.number, 7)
        XCTAssertEqual(second.title, "Keep iid project scoped")
        XCTAssertEqual(second.url?.absoluteString, "https://gitlab.com/other/group-service/-/merge_requests/7")
        XCTAssertEqual(second.author.login, "bob")
        XCTAssertEqual(second.sloClockStart, try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-17T09:00:00Z")))
        XCTAssertEqual(second.additions, 10)
        XCTAssertEqual(second.deletions, 11)
        XCTAssertEqual(second.files, 4)
    }

    func testMapCIMapsGitLabPipelineStatuses() {
        let cases: [(String?, PullRequestCI)] = [
            ("SUCCESS", .passing),
            ("success", .passing),
            ("FAILED", .failing),
            ("RUNNING", .running),
            ("CREATED", .pending),
            ("PENDING", .pending),
            ("MANUAL", .pending),
            ("SCHEDULED", .pending),
            ("CANCELED", .pending),
            ("SKIPPED", .pending),
            ("WAITING_FOR_RESOURCE", .pending),
            ("PREPARING", .pending),
            ("EXPLODING", .pending),
            (nil, .pending),
        ]

        for (status, expected) in cases {
            XCTAssertEqual(GitLabProvider.mapCI(status), expected, "status: \(status ?? "nil")")
        }
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func response(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return response
    }

    private static let dataResponse = Data("""
    { "data": { "ok": true } }
    """.utf8)

    private static let errorsResponse = Data("""
    { "errors": [{ "message": "x" }] }
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
                "author": {
                  "username": "alice",
                  "avatarUrl": "https://gitlab.com/uploads/-/system/user/avatar/1/avatar.png"
                },
                "diffStatsSummary": { "additions": 42, "deletions": 5, "fileCount": 3 }
              },
              {
                "id": "gid://gitlab/MergeRequest/202",
                "iid": "7",
                "title": "Keep iid project scoped",
                "webUrl": "https://gitlab.com/other/group-service/-/merge_requests/7",
                "createdAt": "2026-06-17T09:00:00Z",
                "draft": false,
                "project": { "fullPath": "other/group-service" },
                "author": { "username": "bob", "avatarUrl": null },
                "diffStatsSummary": { "additions": 10, "deletions": 11, "fileCount": 4 }
              },
              {
                "id": "gid://gitlab/MergeRequest/303",
                "iid": "8",
                "title": "Draft should be skipped",
                "webUrl": "https://gitlab.com/namespace/project/-/merge_requests/8",
                "createdAt": "2026-06-17T10:00:00Z",
                "draft": true,
                "project": { "fullPath": "namespace/project" },
                "author": { "username": "carol", "avatarUrl": null },
                "diffStatsSummary": { "additions": 99, "deletions": 99, "fileCount": 9 }
              }
            ]
          }
        }
      }
    }
    """.utf8)
}

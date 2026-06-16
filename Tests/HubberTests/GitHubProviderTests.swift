import Foundation
import XCTest
@testable import Hubber

final class GitHubProviderTests: XCTestCase {
    private var provider: GitHubProvider!

    override func setUp() {
        super.setUp()
        provider = GitHubProvider(session: makeSession())
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    // MARK: - Incoming

    func testFetchIncomingReviewsMapsGraphQLNodes() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.incomingReviewsResponse)
        }

        let reviews = try await provider.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "osuritz",
            mode: .explicit
        )

        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews[0].number, 42)
        XCTAssertEqual(reviews[0].title, "Fix biometric prompt")
        XCTAssertEqual(reviews[0].repo, "acme/ios")
        XCTAssertEqual(reviews[0].author.login, "priyanka")
        XCTAssertEqual(reviews[0].additions, 54)
        XCTAssertEqual(reviews[0].deletions, 29)
        XCTAssertEqual(reviews[0].files, 3)
    }

    func testFetchIncomingReviewsSLOClockUsesMaxOfRequestedAndReady() async throws {
        // reviewRequestedAt = 2026-06-15T08:00:00Z
        // readyForReviewAt  = 2026-06-15T10:00:00Z  ← later, wins
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.incomingWithReadyForReviewResponse)
        }

        let reviews = try await provider.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "osuritz",
            mode: .explicit
        )

        XCTAssertEqual(reviews.count, 1)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-15T10:00:00Z"))
        XCTAssertEqual(reviews[0].sloClockStart, expected)
    }

    func testFetchIncomingReviewsIncludesTeamSearchQueryForTeamMode() async throws {
        MockURLProtocol.handler = { request in
            MockURLProtocol.lastRequest = request
            return try (Self.response(for: request), Self.emptySearchResponse)
        }

        _ = try await provider.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "osuritz",
            mode: .team
        )

        let body = try XCTUnwrap(MockURLProtocol.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let variables = json?["variables"] as? [String: Any]
        let query = variables?["searchQuery"] as? String ?? ""
        XCTAssertTrue(query.contains("team-review-requested:@me"), "Team mode should include team-review-requested")
    }

    func testFetchIncomingReviewsThrowsBadCredentialsOn401() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request, statusCode: 401), Data())
        }

        do {
            _ = try await provider.fetchIncomingReviews(accessToken: "bad", viewerLogin: "osuritz", mode: .explicit)
            XCTFail("Expected badCredentials")
        } catch GitHubAuthError.badCredentials {}
    }

    // MARK: - Helpers (reused across task tests — keep in sync)

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func response(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Fixture JSON

    static let incomingReviewsResponse = Data("""
    {
      "data": {
        "search": {
          "nodes": [{
            "__typename": "PullRequest",
            "id": "PR_kw1",
            "number": 42,
            "title": "Fix biometric prompt",
            "url": "https://github.com/acme/ios/pull/42",
            "isDraft": false,
            "additions": 54,
            "deletions": 29,
            "changedFiles": 3,
            "repository": { "nameWithOwner": "acme/ios" },
            "author": { "login": "priyanka", "avatarUrl": "https://avatars.githubusercontent.com/u/1" },
            "timelineItems": {
              "nodes": [{
                "__typename": "ReviewRequestedEvent",
                "createdAt": "2026-06-15T08:00:00Z",
                "requestedReviewer": { "__typename": "User", "login": "osuritz" }
              }]
            }
          }]
        }
      }
    }
    """.utf8)

    static let incomingWithReadyForReviewResponse = Data("""
    {
      "data": {
        "search": {
          "nodes": [{
            "__typename": "PullRequest",
            "id": "PR_kw2",
            "number": 99,
            "title": "Draft then ready",
            "url": "https://github.com/acme/web/pull/99",
            "isDraft": false,
            "additions": 10,
            "deletions": 2,
            "changedFiles": 1,
            "repository": { "nameWithOwner": "acme/web" },
            "author": { "login": "tobi", "avatarUrl": null },
            "timelineItems": {
              "nodes": [
                {
                  "__typename": "ReviewRequestedEvent",
                  "createdAt": "2026-06-15T08:00:00Z",
                  "requestedReviewer": { "__typename": "User", "login": "osuritz" }
                },
                {
                  "__typename": "ReadyForReviewEvent",
                  "createdAt": "2026-06-15T10:00:00Z"
                }
              ]
            }
          }]
        }
      }
    }
    """.utf8)

    static let emptySearchResponse = Data("""
    { "data": { "search": { "nodes": [] } } }
    """.utf8)
}

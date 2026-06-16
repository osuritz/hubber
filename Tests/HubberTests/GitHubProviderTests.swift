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

    private static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        headerFields: [String: String]? = nil
    ) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard
            let response = HTTPURLResponse(
                url: url, statusCode: statusCode, httpVersion: nil, headerFields: headerFields
            ) else { throw URLError(.badServerResponse) }
        return response
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

    // MARK: - Outgoing

    func testFetchOutgoingPullRequestsMapsGraphQLNodes() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.outgoingPRsResponse)
        }

        let prs = try await provider.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs[0].number, 9830)
        XCTAssertEqual(prs[0].title, "Webhook rotation")
        XCTAssertEqual(prs[0].ci, .passing)
        XCTAssertEqual(prs[0].ciDetail, "12/12 checks")
        XCTAssertEqual(prs[0].unresolved, 0)
        XCTAssertEqual(prs[0].approvals, 1)
        XCTAssertEqual(prs[0].requiredApprovals, 1)
        XCTAssertEqual(prs[0].reviewers.count, 1)
        XCTAssertEqual(prs[0].reviewers[0].state, .approved)
    }

    func testFetchOutgoingPullRequestsCountsUnresolvedThreadsForAllOpenMode() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.outgoingWithUnresolvedResponse)
        }

        let prs = try await provider.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        XCTAssertEqual(prs[0].unresolved, 2) // 2 open non-outdated threads
    }

    func testFetchOutgoingPullRequestsCountsUnresolvedThreadsForReviewOnlyMode() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.outgoingWithUnresolvedResponse)
        }

        let prs = try await provider.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "osuritz",
            unresolvedMode: .reviewOnly
        )

        // Thread 4 has pullRequestReview: null which MUST NOT count (regression test for NSNull fix).
        // Thread 1 has a real CHANGES_REQUESTED review and counts. Result: 1.
        XCTAssertEqual(prs[0].unresolved, 1)
    }

    func testFetchOutgoingPullRequestsCountsUnresolvedThreadsForChangesRequestedMode() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.outgoingWithUnresolvedResponse)
        }

        let prs = try await provider.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "osuritz",
            unresolvedMode: .changesRequested
        )

        // Only thread 1 has a CHANGES_REQUESTED review. Result: 1.
        XCTAssertEqual(prs[0].unresolved, 1)
    }

    func testFetchOutgoingPullRequestsFiltersOutDrafts() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.outgoingWithDraftResponse)
        }

        let prs = try await provider.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )

        XCTAssertTrue(prs.isEmpty)
    }

    static let outgoingPRsResponse = Data("""
    {
      "data": {
        "viewer": {
          "pullRequests": {
            "nodes": [{
              "id": "PR_9830",
              "number": 9830,
              "title": "Webhook rotation",
              "url": "https://github.com/acme/api/pull/9830",
              "isDraft": false,
              "updatedAt": "2026-06-15T09:00:00Z",
              "mergeable": "MERGEABLE",
              "repository": { "nameWithOwner": "acme/api" },
              "commits": {
                "nodes": [{
                  "commit": {
                    "statusCheckRollup": {
                      "state": "SUCCESS",
                      "contexts": {
                        "totalCount": 12,
                        "nodes": []
                      }
                    }
                  }
                }]
              },
              "reviewThreads": { "nodes": [] },
              "latestReviews": {
                "nodes": [{
                  "author": { "login": "kenji", "avatarUrl": null },
                  "state": "APPROVED"
                }]
              }
            }]
          }
        }
      }
    }
    """.utf8)

    static let outgoingWithUnresolvedResponse = Data("""
    {
      "data": {
        "viewer": {
          "pullRequests": {
            "nodes": [{
              "id": "PR_9826",
              "number": 9826,
              "title": "Search debounce",
              "url": "https://github.com/acme/web/pull/9826",
              "isDraft": false,
              "updatedAt": "2026-06-15T08:00:00Z",
              "mergeable": "MERGEABLE",
              "repository": { "nameWithOwner": "acme/web" },
              "commits": { "nodes": [{ "commit": { "statusCheckRollup": null } }] },
              "reviewThreads": {
                "nodes": [
                  {
                    "isResolved": false, "isOutdated": false,
                    "comments": { "nodes": [{ "author": { "login": "tobi" },
                      "pullRequestReview": { "state": "CHANGES_REQUESTED", "author": { "login": "tobi" } } }] }
                  },
                  { "isResolved": true, "isOutdated": false, "comments": { "nodes": [] } },
                  { "isResolved": false, "isOutdated": true, "comments": { "nodes": [] } },
                  {
                    "isResolved": false, "isOutdated": false,
                    "comments": { "nodes": [{ "author": { "login": "ines" }, "pullRequestReview": null }] }
                  }
                ]
              },
              "latestReviews": { "nodes": [] }
            }]
          }
        }
      }
    }
    """.utf8)

    static let outgoingWithDraftResponse = Data("""
    {
      "data": {
        "viewer": {
          "pullRequests": {
            "nodes": [{
              "id": "PR_9835",
              "number": 9835,
              "title": "Draft spike",
              "url": "https://github.com/acme/api/pull/9835",
              "isDraft": true,
              "updatedAt": "2026-06-15T07:00:00Z",
              "mergeable": "UNKNOWN",
              "repository": { "nameWithOwner": "acme/api" },
              "commits": { "nodes": [] },
              "reviewThreads": { "nodes": [] },
              "latestReviews": { "nodes": [] }
            }]
          }
        }
      }
    }
    """.utf8)

    // MARK: - Rate-limit detection

    func testGraphQL429ThrowsRateLimitedWithRetryAfter() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request, statusCode: 429, headerFields: ["Retry-After": "30"]), Data())
        }

        do {
            _ = try await provider.fetchIncomingReviews(accessToken: "tok", viewerLogin: "osuritz", mode: .explicit)
            XCTFail("Expected rateLimited")
        } catch let GitHubAuthError.rateLimited(retryAfter) {
            XCTAssertEqual(retryAfter, 30)
        }
    }

    func testGraphQL403WithRateLimitRemainingZeroThrowsRateLimited() async throws {
        MockURLProtocol.handler = { request in
            try (
                Self.response(
                    for: request,
                    statusCode: 403,
                    headerFields: ["x-ratelimit-remaining": "0", "Retry-After": "60"]
                ),
                Data()
            )
        }

        do {
            _ = try await provider.fetchIncomingReviews(accessToken: "tok", viewerLogin: "osuritz", mode: .explicit)
            XCTFail("Expected rateLimited")
        } catch let GitHubAuthError.rateLimited(retryAfter) {
            XCTAssertEqual(retryAfter, 60)
        }
    }

    func testGraphQL403WithoutRateLimitHeaderThrowsGitHub() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request, statusCode: 403), Data())
        }

        do {
            _ = try await provider.fetchIncomingReviews(accessToken: "tok", viewerLogin: "osuritz", mode: .explicit)
            XCTFail("Expected github error")
        } catch GitHubAuthError.github {
            // expected
        }
    }

    func testGraphQL429WithoutRetryAfterHasNilRetryAfter() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request, statusCode: 429), Data())
        }

        do {
            _ = try await provider.fetchIncomingReviews(accessToken: "tok", viewerLogin: "osuritz", mode: .explicit)
            XCTFail("Expected rateLimited")
        } catch let GitHubAuthError.rateLimited(retryAfter) {
            XCTAssertNil(retryAfter)
        }
    }
}

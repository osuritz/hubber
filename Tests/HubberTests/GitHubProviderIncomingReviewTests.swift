import Foundation
import XCTest
@testable import Hubber

/// Incoming-review filtering and SLO clock behaviour for #144.
final class GitHubProviderIncomingReviewTests: XCTestCase {
    private var provider: GitHubProvider!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        provider = GitHubProvider(session: URLSession(configuration: config))
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    private static func response(for request: URLRequest) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return response
    }

    private static let emptySearchResponse = Data(#"{ "data": { "search": { "nodes": [] } } }"#.utf8)

    // MARK: - Stale search results (#144)

    func testStaleSearchNodeWithoutViewerRequestIsDroppedInBothModes() async throws {
        let requests = #"[{"requestedReviewer": {"__typename": "User", "login": "someone-else"}}]"#
        for mode in [IncomingReviewMode.explicit, .team] {
            let reviews = try await fetchIncoming(node: Self.incomingNode(reviewRequests: requests), mode: mode)
            XCTAssertTrue(reviews.isEmpty, "mode \(mode)")
        }
        let empty = try await fetchIncoming(node: Self.incomingNode(reviewRequests: "[]"), mode: .explicit)
        XCTAssertTrue(empty.isEmpty)
    }

    func testSearchNodeWithViewerRequestIsKept() async throws {
        let requests = #"[{"requestedReviewer": {"__typename": "User", "login": "osuritz"}}]"#
        for mode in [IncomingReviewMode.explicit, .team] {
            let reviews = try await fetchIncoming(node: Self.incomingNode(reviewRequests: requests), mode: mode)
            XCTAssertEqual(reviews.count, 1, "mode \(mode)")
        }
    }

    func testTeamRequestKeepsNodeOnlyInTeamMode() async throws {
        let requests = #"[{"requestedReviewer": {"__typename": "Team", "slug": "core"}}]"#
        let team = try await fetchIncoming(node: Self.incomingNode(reviewRequests: requests), mode: .team)
        XCTAssertEqual(team.count, 1)
        let explicit = try await fetchIncoming(node: Self.incomingNode(reviewRequests: requests), mode: .explicit)
        XCTAssertTrue(explicit.isEmpty)
    }

    func testMissingReviewRequestsFieldKeepsNode() async throws {
        for mode in [IncomingReviewMode.explicit, .team] {
            let reviews = try await fetchIncoming(node: Self.incomingNode(reviewRequests: nil), mode: mode)
            XCTAssertEqual(reviews.count, 1, "mode \(mode)")
        }
    }

    func testIncomingQueryRequestsReviewRequestsAndReviews() async throws {
        var body: String?
        MockURLProtocol.handler = { request in
            body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
                ?? request.httpBodyStream.flatMap(Self.readAll)
            return try (Self.response(for: request), Self.emptySearchResponse)
        }
        _ = try await provider.fetchIncomingReviews(accessToken: "tok", viewerLogin: "osuritz", mode: .explicit)
        let sent = try XCTUnwrap(body)
        XCTAssertTrue(sent.contains("reviewRequests(first: 50)"))
        XCTAssertTrue(sent.contains("PULL_REQUEST_REVIEW"))
    }

    // MARK: - SLO clock after re-request (#144)

    func testSLOClockRestartsOnReRequestAfterViewerReview() async throws {
        let timeline = """
        [
          {"__typename": "ReviewRequestedEvent", "createdAt": "2026-06-15T12:57:00Z",
           "requestedReviewer": {"__typename": "User", "login": "osuritz"}},
          {"__typename": "PullRequestReview", "submittedAt": "2026-06-15T18:28:00Z",
           "author": {"login": "osuritz"}},
          {"__typename": "ReviewRequestedEvent", "createdAt": "2026-06-15T22:14:00Z",
           "requestedReviewer": {"__typename": "User", "login": "osuritz"}}
        ]
        """
        let reviews = try await fetchIncoming(node: Self.incomingNode(timeline: timeline), mode: .explicit)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-15T22:14:00Z"))
        XCTAssertEqual(reviews.first?.sloClockStart, expected)
    }

    func testSLOClockIgnoresOtherPeoplesReviews() async throws {
        let timeline = """
        [
          {"__typename": "ReviewRequestedEvent", "createdAt": "2026-06-15T12:57:00Z",
           "requestedReviewer": {"__typename": "User", "login": "osuritz"}},
          {"__typename": "PullRequestReview", "submittedAt": "2026-06-15T18:28:00Z",
           "author": {"login": "someone-else"}},
          {"__typename": "ReviewRequestedEvent", "createdAt": "2026-06-15T22:14:00Z",
           "requestedReviewer": {"__typename": "User", "login": "osuritz"}}
        ]
        """
        let reviews = try await fetchIncoming(node: Self.incomingNode(timeline: timeline), mode: .explicit)
        let expected = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-15T12:57:00Z"))
        XCTAssertEqual(reviews.first?.sloClockStart, expected)
    }

    private func fetchIncoming(node: String, mode: IncomingReviewMode) async throws -> [IncomingReview] {
        let data = Data(#"{"data": {"search": {"nodes": [\#(node)]}}}"#.utf8)
        MockURLProtocol.handler = { request in try (Self.response(for: request), data) }
        return try await provider.fetchIncomingReviews(accessToken: "tok", viewerLogin: "osuritz", mode: mode)
    }

    private static func readAll(_ stream: InputStream) -> String? {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func incomingNode(reviewRequests: String? = nil, timeline: String = "[]") -> String {
        let requests = reviewRequests.map { #""reviewRequests": {"nodes": \#($0)},"# } ?? ""
        return """
        {
          "__typename": "PullRequest", "id": "PR_x", "number": 1, "title": "t",
          "url": "https://github.com/acme/web/pull/1", "isDraft": false,
          "additions": 1, "deletions": 1, "changedFiles": 1,
          "repository": { "nameWithOwner": "acme/web" },
          "author": { "login": "tobi", "avatarUrl": null },
          \(requests)
          "timelineItems": { "nodes": \(timeline) }
        }
        """
    }
}

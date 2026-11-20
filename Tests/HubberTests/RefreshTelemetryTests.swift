import Foundation
import XCTest
@testable import Hubber

private actor EmptyProvider: CodeHostProvider {
    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        []
    }

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        []
    }

    func fetchDraftPullRequests(accessToken: String, limit: Int) async throws -> [DraftReview] {
        []
    }
}

/// `refresh.manual` must only be sent for user-initiated refreshes, not for automatic ones (wake from sleep).
@MainActor
final class RefreshTelemetryTests: XCTestCase {
    private func makeSignedInStore(spy: SpyTelemetrySink) async throws -> HubberStore {
        let token = StoredToken(
            accessToken: "test-token",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: "testuser"
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { _ in
            guard
                let url = URL(string: "https://api.github.com/user"),
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badURL)
            }
            return try (response, JSONSerialization.data(withJSONObject: ["login": "testuser"]))
        }
        let store = HubberStore(
            authService: GitHubAuthService(clientID: "test", session: URLSession(configuration: config)),
            provider: EmptyProvider(),
            tokenStore: SpyTokenStore(token: token),
            telemetry: Telemetry(sink: spy)
        )
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !(store.canRefreshPullRequests && !store.isRefreshingPullRequests) {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(store.canRefreshPullRequests, "Store must be signed in and idle")
        return store
    }

    func testUserInitiatedRefreshSendsOneManualRefreshEvent() async throws {
        let spy = SpyTelemetrySink()
        let store = try await makeSignedInStore(spy: spy)

        store.refreshPullRequests(userInitiated: true)

        XCTAssertEqual(spy.calls.filter { $0.event == "refresh.manual" }.count, 1)
    }

    func testAutomaticRefreshSendsNoManualRefreshEvent() async throws {
        let spy = SpyTelemetrySink()
        let store = try await makeSignedInStore(spy: spy)

        store.refreshPullRequests(userInitiated: false)

        XCTAssertTrue(spy.calls.filter { $0.event == "refresh.manual" }.isEmpty)
    }
}

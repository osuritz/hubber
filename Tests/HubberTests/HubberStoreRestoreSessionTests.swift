import Foundation
import XCTest
@testable import Hubber

// MARK: - Spy token store

/// A spy `GitHubTokenStoring` that loads a pre-configured token and records whether
/// `delete()` was ever called. All methods are safe to call from any thread.
final class SpyTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private let storedToken: GitHubStoredToken?
    private let lock = NSLock()
    private var _deleteCallCount = 0

    var deleteCallCount: Int {
        lock.withLock { _deleteCallCount }
    }

    init(token: GitHubStoredToken?) {
        storedToken = token
    }

    func load() throws -> GitHubStoredToken? {
        storedToken
    }

    func save(_ token: GitHubStoredToken) throws {
        // no-op: the test does not exercise save
    }

    func delete() throws {
        lock.withLock { _deleteCallCount += 1 }
    }
}

// MARK: - Integration tests

@MainActor
final class HubberStoreRestoreSessionTests: XCTestCase {

    /// On a 401 response during session restore, when the stored token has a known login:
    /// - `authState` must become `.sessionExpired(login:)` (not `.signedOut`)
    /// - `delete()` on the token store must NOT be called (token is preserved for re-auth)
    func testRestoreSession401SetsSessionExpiredAndPreservesToken() async throws {

        // MARK: Arrange

        // Token with a fresh access token (no refresh needed) and a known login.
        // `hasFreshAccessToken` returns true when `accessTokenExpiresAt` is nil, so
        // omitting it causes restoreSession to skip the refresh step and go straight
        // to `fetchAuthenticatedUser` — which our mock will answer with 401.
        let knownLogin = "testuser-session-restore"
        let fakeToken = GitHubStoredToken(
            accessToken: "fake-access-token",
            accessTokenExpiresAt: nil, // nil → hasFreshAccessToken == true
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: knownLogin
        )
        let spyStore = SpyTokenStore(token: fakeToken)

        // URLSession backed by MockURLProtocol; every request to api.github.com/user
        // returns HTTP 401 so GitHubAuthService.fetchAuthenticatedUser throws .badCredentials.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { _ in
            guard
                let url = URL(string: "https://api.github.com/user"),
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 401,
                    httpVersion: nil,
                    headerFields: nil
                )
            else {
                throw URLError(.badURL)
            }
            return (response, Data())
        }
        let mockSession = URLSession(configuration: config)
        let authService = GitHubAuthService(clientID: "test-client-id", session: mockSession)

        // MARK: Act

        let store = HubberStore(
            authService: authService,
            provider: CachingCodeHostProvider(wrapping: NoOpProvider()),
            tokenStore: spyStore
        )

        // `restoreSession()` is called from `init` and runs in a Task. Poll until
        // authState leaves `.restoring` (or timeout after ~2s).
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if case .restoring = store.authState {
                try await Task.sleep(for: .milliseconds(50))
            } else {
                break
            }
        }

        // MARK: Assert

        XCTAssertEqual(
            store.authState,
            .sessionExpired(login: knownLogin),
            "A 401 during restore with a known login must produce .sessionExpired, not .signedOut"
        )
        XCTAssertEqual(
            spyStore.deleteCallCount,
            0,
            "Token must NOT be deleted when session expires — it is needed for re-authentication"
        )
    }
}

// MARK: - Minimal no-op provider for this test fixture

private actor NoOpProvider: CodeHostProvider {
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

    func fetchDraftPullRequests(
        accessToken: String,
        limit: Int
    ) async throws -> [DraftReview] {
        []
    }
}

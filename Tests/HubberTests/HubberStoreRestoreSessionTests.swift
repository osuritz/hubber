import Foundation
import XCTest
@testable import Hubber

// MARK: - Spy token store

/// A spy `TokenStoring` that loads a pre-configured token and records whether
/// `delete()` was ever called. All methods are safe to call from any thread.
final class SpyTokenStore: TokenStoring, @unchecked Sendable {
    private let storedToken: StoredToken?
    private let lock = NSLock()
    private var _deleteCallCount = 0

    var deleteCallCount: Int {
        lock.withLock { _deleteCallCount }
    }

    init(token: StoredToken?) {
        storedToken = token
    }

    func load() throws -> StoredToken? {
        storedToken
    }

    func save(_ token: StoredToken) throws {
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
        let knownLogin = "testuser-session-restore"
        let spyStore = SpyTokenStore(token: makeTokenWithKnownLogin(knownLogin))
        let store = makeStore401(spyStore: spyStore)

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

    // MARK: - Helpers

    /// Token with a fresh access token (no refresh needed) and a known login.
    /// `hasFreshAccessToken` is true when `accessTokenExpiresAt` is nil, so
    /// restoreSession skips refresh and goes straight to `fetchAuthenticatedUser`.
    private func makeTokenWithKnownLogin(_ login: String) -> StoredToken {
        StoredToken(
            accessToken: "fake-access-token",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: login
        )
    }

    /// Builds a `HubberStore` whose `GitHubAuthService` returns HTTP 401 for every request.
    private func makeStore401(spyStore: SpyTokenStore) -> HubberStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.handler = { _ in
            guard
                let url = URL(string: "https://api.github.com/user"),
                let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)
            else {
                throw URLError(.badURL)
            }
            return (response, Data())
        }
        let authService = GitHubAuthService(clientID: "test-client-id", session: URLSession(configuration: config))
        return HubberStore(
            authService: authService,
            provider: CachingCodeHostProvider(wrapping: NoOpProvider()),
            tokenStore: spyStore
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

import Foundation
import XCTest
@testable import Hubber

// MARK: - Local test doubles (other files' doubles are file-private)

private struct PATStubProvider: CodeHostProvider {
    func fetchIncomingReviews(
        accessToken _: String,
        viewerLogin _: String,
        mode _: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        []
    }

    func fetchOutgoingPullRequests(
        accessToken _: String,
        viewerLogin _: String,
        unresolvedMode _: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        []
    }

    func fetchDraftPullRequests(accessToken _: String, limit _: Int) async throws -> [DraftReview] {
        []
    }
}

private struct PATIdleProvider: MachineIdleProviding { let isIdle = false }

private final class PATAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    let user: GitHubAuthenticatedUser
    private(set) var fetchUserCallCount = 0

    init(user: GitHubAuthenticatedUser) {
        self.user = user
    }

    func fetchAuthenticatedUser(accessToken _: String) async throws -> GitHubAuthenticatedUser {
        fetchUserCallCount += 1
        return user
    }

    func refresh(_: GitHubStoredToken) async throws -> GitHubStoredToken {
        throw GitHubAuthError.missingRefreshToken
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        throw GitHubAuthError.invalidResponse
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        throw GitHubAuthError.invalidResponse
    }
}

private final class PATTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private var token: GitHubStoredToken?

    func load() throws -> GitHubStoredToken? {
        token
    }

    func save(_ token: GitHubStoredToken) throws {
        self.token = token
    }

    func delete() throws {
        token = nil
    }
}

@MainActor
final class ConnectionPATSignInTests: XCTestCase {
    private func makeConnection(
        id: ConnectionID,
        authService: any GitHubDeviceFlowServicing,
        tokenStore: any GitHubTokenStoring,
        settings: SettingsStore
    ) -> Connection {
        Connection(
            id: id,
            provider: PATStubProvider(),
            authService: authService,
            tokenStore: tokenStore,
            snapshotStore: SnapshotStore(
                snapshotURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            scheduler: RefreshScheduler(idle: PATIdleProvider()),
            settings: settings
        )
    }

    func testPATSignInResolvesLoginAndStoresNonRefreshableToken() async throws {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let store = PATTokenStore()
        let auth = PATAuthService(user: GitHubAuthenticatedUser(login: "osuritz", name: "O", avatarUrl: nil))
        let suite = "PAT-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let conn = makeConnection(id: id, authService: auth, tokenStore: store, settings: settings)

        await conn.signIn(withToken: "glpat-secret")

        XCTAssertEqual(conn.authState, .signedIn(login: "osuritz"))
        let saved = try store.load()
        XCTAssertEqual(saved?.accessToken, "glpat-secret")
        XCTAssertNil(saved?.refreshToken)
        XCTAssertNil(saved?.accessTokenExpiresAt)
        XCTAssertEqual(saved?.login, "osuritz")
    }

    func testPATSignInBlockedByHostPolicy() async throws {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let suite = "PAT-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let managed = InMemoryManagedPreferences([ManagedKey.providerAllowlist: ["github.com"]])
        let settings = SettingsStore(defaults: defaults, managed: managed) // gitlab.com NOT allowed
        let auth = PATAuthService(user: GitHubAuthenticatedUser(login: "osuritz", name: nil, avatarUrl: nil))
        let conn = makeConnection(id: id, authService: auth, tokenStore: PATTokenStore(), settings: settings)

        await conn.signIn(withToken: "glpat-secret")

        guard case .error = conn.authState else { return XCTFail("expected .error, got \(conn.authState)") }
        XCTAssertEqual(auth.fetchUserCallCount, 0) // gate runs BEFORE validation
    }
}

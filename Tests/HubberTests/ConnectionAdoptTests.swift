import Foundation
import XCTest
@testable import Hubber

private struct AdoptStubProvider: CodeHostProvider {
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

private struct AdoptIdleProvider: MachineIdleProviding { let isIdle = false }

private final class AdoptTokenStore: TokenStoring, @unchecked Sendable {
    private var token: StoredToken?

    func load() throws -> StoredToken? {
        token
    }

    func save(_ token: StoredToken) throws {
        self.token = token
    }

    func delete() throws {
        token = nil
    }
}

private final class AdoptAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    func fetchAuthenticatedUser(accessToken _: String) async throws -> AuthenticatedUser {
        AuthenticatedUser(login: "x", name: nil, avatarUrl: nil)
    }

    func refresh(_: StoredToken) async throws -> StoredToken {
        throw CodeHostAuthError.missingRefreshToken
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        throw CodeHostAuthError.invalidResponse
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> StoredToken {
        throw CodeHostAuthError.invalidResponse
    }
}

@MainActor
final class ConnectionAdoptTests: XCTestCase {
    private func makeConnection(
        id: ConnectionID,
        store: any TokenStoring,
        settings: SettingsStore
    ) -> Connection {
        Connection(
            id: id,
            provider: AdoptStubProvider(),
            authService: AdoptAuthService(),
            tokenStore: store,
            snapshotStore: SnapshotStore(
                snapshotURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            ),
            scheduler: RefreshScheduler(idle: AdoptIdleProvider()),
            settings: settings
        )
    }

    func testAdoptStoresTokenAndFinishesSession() async throws {
        let suite = "adopt-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let store = AdoptTokenStore()
        let conn = makeConnection(
            id: .gitHubDotCom(login: "osuritz"),
            store: store,
            settings: settings
        )

        let token = StoredToken(
            accessToken: "gho_x",
            accessTokenExpiresAt: nil,
            refreshToken: "ghr_refresh",
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: "osuritz"
        )
        await conn.adopt(
            token: token,
            user: AuthenticatedUser(login: "osuritz", name: "O", avatarUrl: nil)
        )

        XCTAssertEqual(conn.authState, .signedIn(login: "osuritz"))
        XCTAssertEqual(conn.viewerName, "O")
        let saved = try store.load()
        XCTAssertEqual(saved?.accessToken, "gho_x")
        XCTAssertEqual(saved?.refreshToken, "ghr_refresh")
    }
}

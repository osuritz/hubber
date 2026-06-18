import Foundation
import XCTest
@testable import Hubber

private struct AddResolvedStubProvider: CodeHostProvider {
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

private struct AddResolvedIdleProvider: MachineIdleProviding { let isIdle = false }

private final class AddResolvedTokenStore: GitHubTokenStoring, @unchecked Sendable {
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
final class AddResolvedAccountTests: XCTestCase {
    private func makeStore(_ defaults: UserDefaults) -> HubberStore {
        let settings = SettingsStore(defaults: defaults)
        return HubberStore(
            settings: settings,
            defaults: defaults,
            restoreOnInit: false,
            connectionFactory: { id in
                Connection(
                    id: id,
                    provider: AddResolvedStubProvider(),
                    authService: ConnectionFactory.authService(provider: id.provider, host: id.host),
                    tokenStore: AddResolvedTokenStore(),
                    snapshotStore: SnapshotStore(
                        snapshotURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    ),
                    scheduler: RefreshScheduler(idle: AddResolvedIdleProvider()),
                    settings: settings
                )
            }
        )
    }

    func testAddResolvedAccountMaterializesGitLabConnection() async throws {
        let suite = "ara-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults)

        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let token = GitHubStoredToken(
            accessToken: "glpat",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: "osuritz"
        )
        let conn = try await store.addResolvedAccount(
            id: id,
            token: token,
            user: GitHubAuthenticatedUser(login: "osuritz", name: nil, avatarUrl: nil)
        )

        XCTAssertEqual(conn.authState, .signedIn(login: "osuritz"))
        XCTAssertTrue(store.connections.contains { $0.id == id })
        XCTAssertTrue(conn.authService is GitLabAuthService)
    }

    func testAddResolvedAccountRejectsDuplicate() async throws {
        let suite = "ara-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults)
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let token = GitHubStoredToken(
            accessToken: "glpat",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: "osuritz"
        )
        let user = GitHubAuthenticatedUser(login: "osuritz", name: nil, avatarUrl: nil)
        _ = try await store.addResolvedAccount(id: id, token: token, user: user)

        do {
            _ = try await store.addResolvedAccount(id: id, token: token, user: user)
            XCTFail("expected alreadyAdded")
        } catch HubberStore.AddAccountError.alreadyAdded {
            // expected
        }
    }
}

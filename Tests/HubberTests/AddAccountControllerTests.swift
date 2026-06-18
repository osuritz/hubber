import Foundation
import XCTest
@testable import Hubber

private final class FakeAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    var userResult: Result<GitHubAuthenticatedUser, Error> = .success(
        GitHubAuthenticatedUser(login: "osuritz", name: "O", avatarUrl: nil)
    )
    var deviceAuth = GitHubDeviceAuthorization(
        deviceCode: "d",
        userCode: "ABCD-1234",
        verificationURI: URL(string: "https://github.com/login/device")!,
        expiresAt: Date().addingTimeInterval(900),
        interval: 1
    )
    var pollToken = GitHubStoredToken(
        accessToken: "gho_x",
        accessTokenExpiresAt: nil,
        refreshToken: "ghr",
        refreshTokenExpiresAt: nil,
        tokenType: "bearer",
        login: nil
    )
    private(set) var fetchCount = 0

    func fetchAuthenticatedUser(accessToken _: String) async throws -> GitHubAuthenticatedUser {
        fetchCount += 1
        return try userResult.get()
    }

    func refresh(_: GitHubStoredToken) async throws -> GitHubStoredToken {
        throw GitHubAuthError.missingRefreshToken
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        deviceAuth
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        pollToken
    }
}

private typealias AddAccountCallback = (ConnectionID, GitHubStoredToken, GitHubAuthenticatedUser) async throws -> Void

@MainActor
final class AddAccountControllerTests: XCTestCase {
    private func make(
        auth: FakeAuthService = FakeAuthService(),
        policy: ProviderAccessPolicy = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: []),
        onAdd: @escaping AddAccountCallback = { _, _, _ in }
    ) -> AddAccountController {
        AddAccountController(
            policy: policy,
            authServiceFactory: { _, _ in auth },
            addAccount: onAdd
        )
    }

    func testTokenSignInResolvesLoginAndAdds() async {
        var added: ConnectionID?
        let c = make(onAdd: { id, token, _ in
            added = id
            XCTAssertNil(token.refreshToken)
            XCTAssertEqual(token.accessToken, "glpat")
        })
        await c.connectWithToken(provider: .gitLab, serverURL: "https://gitlab.com", token: "glpat")
        XCTAssertEqual(added, ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz"))
        guard case .added = c.stage else { return XCTFail("expected .added, got \(c.stage)") }
    }

    func testBadTokenSurfacesError() async {
        let auth = FakeAuthService()
        auth.userResult = .failure(GitHubAuthError.badCredentials)
        let c = make(auth: auth)
        await c.connectWithToken(provider: .gitLab, serverURL: "https://gitlab.com", token: "bad")
        guard case .failed = c.stage else { return XCTFail("expected .failed") }
    }

    func testBlockedHostFailsBeforeFetch() async {
        let auth = FakeAuthService()
        let policy = ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: ["github.com"])
        let c = make(auth: auth, policy: policy)
        await c.connectWithToken(provider: .gitLab, serverURL: "https://gitlab.com", token: "x")
        guard case .failed = c.stage else { return XCTFail("expected .failed") }
        XCTAssertEqual(auth.fetchCount, 0)
    }

    func testDeviceFlowHappyPath() async {
        var added: ConnectionID?
        let c = make(onAdd: { id, token, _ in
            added = id
            XCTAssertEqual(token.refreshToken, "ghr")
            XCTAssertEqual(token.login, "osuritz")
        })
        await c.beginDeviceFlow()
        XCTAssertEqual(added, ConnectionID.gitHubDotCom(login: "osuritz"))
        guard case .added = c.stage else { return XCTFail("expected .added, got \(c.stage)") }
    }
}

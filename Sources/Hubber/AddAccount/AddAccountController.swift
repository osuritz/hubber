import AppKit
import Combine
import Foundation

/// The three add-account provider kinds (spec decision #7).
enum AddAccountProvider: String, CaseIterable, Identifiable {
    case gitHubDotCom
    case gitHubEnterprise
    case gitLab

    var id: String {
        rawValue
    }

    var providerString: String {
        self == .gitLab ? "gitlab" : "github"
    }

    var title: String {
        switch self {
        case .gitHubDotCom:
            "GitHub.com"
        case .gitHubEnterprise:
            "GitHub Enterprise Server"
        case .gitLab:
            "GitLab"
        }
    }

    /// github.com is fixed; the others take a user-entered server URL.
    var usesDeviceFlow: Bool {
        self == .gitHubDotCom
    }

    var defaultServerURL: String {
        self == .gitLab ? "https://gitlab.com" : ""
    }
}

/// Drives the add-account flow: gate `canConnect(host:)` -> device-flow OR PAT -> resolve login ->
/// hand a fully-resolved identity to `addAccount`. Pure of `Connection`/scheduler (the `addAccount`
/// closure is injected; production wires it to `HubberStore.addResolvedAccount`).
@MainActor
final class AddAccountController: ObservableObject {
    enum Stage: Equatable {
        case picker
        case form(AddAccountProvider)
        case authenticating
        case deviceCode(GitHubDeviceAuthorization)
        case failed(String)
        case added(ConnectionID)
    }

    @Published private(set) var stage: Stage = .picker
    @Published var selectedProvider: AddAccountProvider = .gitHubDotCom

    private let policy: ProviderAccessPolicy
    private let authServiceFactory: (_ provider: String, _ host: String) -> any GitHubDeviceFlowServicing
    private let isDuplicate: (ConnectionID) -> Bool
    private let addAccount: (ConnectionID, GitHubStoredToken, GitHubAuthenticatedUser) async throws -> Void

    private var currentAuthorization: GitHubDeviceAuthorization?

    /// Resolved-but-not-yet-materialized account. We reach `.added` (and play the success animation
    /// in the dialog) BEFORE materializing, so the new connection's sign-in/refresh churn doesn't
    /// re-render and tear down the dialog mid-animation. `finalize()` materializes it afterward.
    private struct PendingAccount {
        let id: ConnectionID
        let token: GitHubStoredToken
        let user: GitHubAuthenticatedUser
    }

    private var pending: PendingAccount?

    init(
        policy: ProviderAccessPolicy,
        authServiceFactory: @escaping (String, String) -> any GitHubDeviceFlowServicing = {
            ConnectionFactory.authService(provider: $0, host: $1)
        },
        isDuplicate: @escaping (ConnectionID) -> Bool = { _ in false },
        addAccount: @escaping (ConnectionID, GitHubStoredToken, GitHubAuthenticatedUser) async throws -> Void
    ) {
        self.policy = policy
        self.authServiceFactory = authServiceFactory
        self.isDuplicate = isDuplicate
        self.addAccount = addAccount
    }

    /// Materializes the account resolved by `connectWithToken`/`beginDeviceFlow`. Called by the
    /// dialog AFTER the success animation finishes, so the refresh churn happens as the dialog
    /// closes — never during the animation.
    func finalize() async {
        guard let pending else { return }
        self.pending = nil
        try? await addAccount(pending.id, pending.token, pending.user)
    }

    func choose(_ provider: AddAccountProvider) {
        selectedProvider = provider
        stage = .form(provider)
    }

    func reset() {
        stage = .picker
    }

    // MARK: - PAT path (GitLab / GHES / EMU github.com)

    func connectWithToken(provider: AddAccountProvider, serverURL: String, token: String) async {
        let host = Self.host(from: serverURL, provider: provider)
        guard policy.canConnect(host: host) else {
            stage = .failed(policy.blockedReason(host: host) ?? "Sign-in is restricted by your organization.")
            return
        }
        stage = .authenticating
        let auth = authServiceFactory(provider.providerString, host)
        do {
            let user = try await auth.fetchAuthenticatedUser(accessToken: token)
            let id = ConnectionID(provider: provider.providerString, host: host, login: user.login)
            guard !isDuplicate(id) else {
                stage = .failed("This account is already added.")
                return
            }
            let stored = GitHubStoredToken(
                accessToken: token,
                accessTokenExpiresAt: nil,
                refreshToken: nil,
                refreshTokenExpiresAt: nil,
                tokenType: "bearer",
                login: user.login
            )
            pending = PendingAccount(id: id, token: stored, user: user)
            stage = .added(id)
        } catch GitHubAuthError.badCredentials {
            stage = .failed("That token was rejected. Check the token and its scopes.")
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    // MARK: - Device-flow path (github.com)

    func beginDeviceFlow() async {
        let host = "github.com"
        guard policy.canConnect(host: host) else {
            stage = .failed(policy.blockedReason(host: host) ?? "Sign-in is restricted by your organization.")
            return
        }
        let auth = authServiceFactory("github", host)
        do {
            let authorization = try await auth.startDeviceFlow()
            currentAuthorization = authorization
            stage = .deviceCode(authorization)
            var token = try await auth.pollForToken(deviceAuthorization: authorization)
            let user = try await auth.fetchAuthenticatedUser(accessToken: token.accessToken)
            token.login = user.login
            let id = ConnectionID.gitHubDotCom(login: user.login)
            guard !isDuplicate(id) else {
                stage = .failed("This account is already added.")
                return
            }
            pending = PendingAccount(id: id, token: token, user: user)
            stage = .added(id)
        } catch is CancellationError {
            stage = .picker
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    func openDeviceVerificationPage() {
        guard let url = currentAuthorization?.verificationURI else { return }
        NSWorkspace.shared.open(url)
    }

    func copyDeviceCode() {
        guard let code = currentAuthorization?.userCode else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    func cancel() {
        stage = .picker
    }

    // MARK: - Host parsing

    /// github.com is fixed; otherwise derive the host from the entered server URL.
    static func host(from serverURL: String, provider: AddAccountProvider) -> String {
        if provider == .gitHubDotCom { return "github.com" }
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let comps = URLComponents(string: trimmed), let h = comps.host { return h }
        return trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
    }
}

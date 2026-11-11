import AppKit
import Foundation

@MainActor
final class Connection: ObservableObject, Identifiable {
    let id: ConnectionID
    @Published var authState: HubberAuthState = .restoring
    @Published private(set) var viewerName: String?
    @Published private(set) var viewerAvatarURL: URL?
    @Published private(set) var data = HubberData(incoming: [], outgoing: [], drafts: [])
    @Published private(set) var isRefreshingPullRequests = false
    @Published private(set) var lastPullRequestRefresh: Date?
    @Published var incomingError: String?
    @Published var outgoingError: String?
    @Published var draftsError: String?
    @Published var pullRequestRefreshError: String?
    @Published var rateLimitedUntil: Date?
    @Published private(set) var developerLog: [DeveloperLogEntry] = []
    @Published var isPopoverOpen = false

    var notificationBaseline: ReviewSnapshot?
    var onRefreshSucceeded: ((TabSuccesses) async -> Void)?
    var onSignedIn: (() async -> Void)?

    let provider: any CodeHostProvider
    let authService: any CodeHostAuthServicing
    let tokenStore: any TokenStoring
    let snapshotStore: SnapshotStore
    let scheduler: RefreshScheduler
    let settings: SettingsStore

    private var authTask: Task<Void, Never>?
    private var isRefreshLoopRunning = false

    init(
        id: ConnectionID,
        provider: any CodeHostProvider,
        authService: any CodeHostAuthServicing,
        tokenStore: any TokenStoring,
        snapshotStore: SnapshotStore,
        scheduler: RefreshScheduler,
        settings: SettingsStore
    ) {
        self.id = id
        self.provider = provider
        self.authService = authService
        self.tokenStore = tokenStore
        self.snapshotStore = snapshotStore
        self.scheduler = scheduler
        self.settings = settings
        notificationBaseline = snapshotStore.load()
    }

    func restoreSession() {
        appendDeveloperLog("Restoring saved GitHub session")
        appendDeveloperLog("Token storage: \(tokenStoreDescription)")
        authTask?.cancel()
        authTask = Task {
            var cachedLogin: String?

            do {
                guard var token = try await loadStoredToken() else {
                    authState = .signedOut
                    appendDeveloperLog("No saved GitHub token found")
                    return
                }

                cachedLogin = token.login
                if let login = cachedLogin {
                    useCachedLogin(login)
                } else {
                    authState = .restoring
                }

                if !token.hasFreshAccessToken {
                    appendDeveloperLog("Refreshing expired GitHub access token")
                    token = try await authService.refresh(token)
                }

                let user: AuthenticatedUser
                do {
                    user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
                } catch CodeHostAuthError.badCredentials where token.canRefresh {
                    token = try await authService.refresh(token)
                    user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
                }

                token.login = user.login
                try await saveStoredToken(token)
                finishSignedInSession(login: user.login, name: user.name, avatarUrl: user.avatarUrl)
            } catch CodeHostAuthError.badCredentials, CodeHostAuthError.missingRefreshToken {
                await handleRestoreCredentialError(cachedLogin: cachedLogin)
            } catch {
                handleRestoreGenericError(error, cachedLogin: cachedLogin)
            }
        }
    }

    func startSignIn(policy: ProviderAccessPolicy) {
        guard policy.canConnectGitHubDotCom else {
            let reason = policy.blockedReason ?? "Sign-in is restricted by your organization."
            appendDeveloperLog("Sign-in blocked by policy: \(reason)")
            authTask?.cancel()
            authTask = nil
            authState = .error(reason)
            return
        }

        appendDeveloperLog("Starting GitHub device sign-in")
        authTask?.cancel()
        authTask = Task {
            do {
                guard let deviceFlow = authService as? GitHubDeviceFlowServicing else {
                    authState = .error("This account type doesn't support device sign-in.")
                    appendDeveloperLog("Device sign-in unavailable for this provider")
                    stopPullRequestRefreshLoop()
                    return
                }
                authState = .restoring
                let deviceAuthorization = try await deviceFlow.startDeviceFlow()
                authState = .waitingForUser(deviceAuthorization)
                appendDeveloperLog("Waiting for GitHub device authorization")

                var token = try await deviceFlow.pollForToken(deviceAuthorization: deviceAuthorization)
                let user = try await deviceFlow.fetchAuthenticatedUser(accessToken: token.accessToken)
                token.login = user.login
                try await saveStoredToken(token)
                finishSignedInSession(login: user.login, name: user.name, avatarUrl: user.avatarUrl)
            } catch is CancellationError {
                authState = .signedOut
                appendDeveloperLog("GitHub sign-in cancelled")
                stopPullRequestRefreshLoop()
            } catch {
                authState = .error(error.localizedDescription)
                appendDeveloperLog("GitHub sign-in failed: \(error.localizedDescription)")
                stopPullRequestRefreshLoop()
            }
        }
    }

    /// Token-based sign-in (Personal Access Token) for providers without device flow
    /// (GitLab, GitHub Enterprise, EMU/company github.com accounts). Validates the token by
    /// resolving the authenticated user, stores a non-refreshable token, and starts the session.
    func signIn(withToken token: String) async {
        let policy = settings.providerAccessPolicy
        guard policy.canConnect(host: id.host) else {
            let reason = policy.blockedReason(host: id.host) ?? "Sign-in is restricted by your organization."
            appendDeveloperLog("Token sign-in blocked by policy: \(reason)")
            authState = .error(reason)
            return
        }

        authState = .restoring
        do {
            let user = try await authService.fetchAuthenticatedUser(accessToken: token)
            let stored = StoredToken(
                accessToken: token,
                accessTokenExpiresAt: nil,
                refreshToken: nil,
                refreshTokenExpiresAt: nil,
                tokenType: "bearer",
                login: user.login
            )
            try await saveStoredToken(stored)
            finishSignedInSession(login: user.login, name: user.name, avatarUrl: user.avatarUrl)
        } catch CodeHostAuthError.badCredentials {
            authState = .error("That token was rejected. Check the token and its scopes.")
            appendDeveloperLog("Token sign-in rejected (bad credentials)")
        } catch {
            authState = .error(error.localizedDescription)
            appendDeveloperLog("Token sign-in failed: \(error.localizedDescription)")
        }
    }

    /// Adopts an already-validated token + resolved user from an external auth flow (multi-account
    /// add, where the login was resolved before this Connection existed). Stores the token as-is,
    /// preserving a device-flow refresh token, and finishes the session without re-fetching.
    func adopt(token: StoredToken, user: AuthenticatedUser) async {
        authState = .restoring
        do {
            try await saveStoredToken(token)
            finishSignedInSession(login: user.login, name: user.name, avatarUrl: user.avatarUrl)
        } catch {
            authState = .error(error.localizedDescription)
            appendDeveloperLog("Adopt token failed: \(error.localizedDescription)")
        }
    }

    func cancelSignIn() {
        authTask?.cancel()
        authTask = nil
        authState = .signedOut
        appendDeveloperLog("GitHub sign-in cancelled")
        stopPullRequestRefreshLoop()
    }

    func signOut() async {
        appendDeveloperLog("Signing out")
        authTask?.cancel()
        stopPullRequestRefreshLoop()
        do {
            if let invalidating = provider as? CodeHostCacheInvalidating {
                await invalidating.invalidateAll()
            }
            try await deleteStoredToken()
            authState = .signedOut
            viewerName = nil
            viewerAvatarURL = nil
            data = HubberData(incoming: [], outgoing: [], drafts: [])
            lastPullRequestRefresh = nil
            pullRequestRefreshError = nil
            setTabError(nil, for: .incoming)
            setTabError(nil, for: .outgoing)
            setTabError(nil, for: .drafts)
            appendDeveloperLog("Signed out and cleared saved GitHub token")
        } catch {
            authState = .error(error.localizedDescription)
            appendDeveloperLog("Sign out failed: \(error.localizedDescription)")
        }
    }

    func openDeviceVerificationPage() {
        if case let .waitingForUser(authorization) = authState {
            NSWorkspace.shared.open(authorization.verificationURI)
        }
    }

    func copyDeviceCode() {
        if case let .waitingForUser(authorization) = authState {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(authorization.userCode, forType: .string)
        }
    }

    func refreshNow() {
        guard canRefreshPullRequests, !isRefreshingPullRequests else {
            appendDeveloperLog("Ignored manual refresh request")
            return
        }

        if isRefreshLoopRunning {
            scheduler.reset()
        } else {
            startPullRequestRefreshLoop()
        }
    }

    func replaceData(_ data: HubberData) {
        self.data = data
    }

    @discardableResult
    func refreshPullRequestsFromGitHub() async -> TabSuccesses? {
        guard canRefreshPullRequests, !isRefreshingPullRequests else { return nil }
        guard rateLimitedUntil.map({ $0 > Date() }) != true else {
            let until = rateLimitedUntil.map { Self.developerLogFormatter.string(from: $0) } ?? "unknown"
            appendDeveloperLog("Skipped refresh: rate-limited until \(until)")
            return nil
        }
        guard let login = signedInLogin else {
            appendDeveloperLog("Skipped refresh: no signed-in login")
            return nil
        }

        isRefreshingPullRequests = true
        defer { isRefreshingPullRequests = false }

        let token: StoredToken
        do {
            token = try await freshStoredToken()
        } catch is CancellationError {
            appendDeveloperLog("Pull request refresh cancelled")
            return nil
        } catch {
            await handleRefreshError(error)
            return nil
        }

        appendDeveloperLog("Refreshing all tabs for @\(login)")
        let (didStop, tabSuccesses) = await fetchAllTabsIndependently(token: token, login: login)
        if didStop {
            return nil
        }

        lastPullRequestRefresh = Date()
        pullRequestRefreshError = nil
        rateLimitedUntil = nil
        let counts = "\(data.incoming.count) incoming, \(data.outgoing.count) outgoing, \(data.drafts.count) drafts"
        appendDeveloperLog("Fetched \(counts)")
        await onRefreshSucceeded?(tabSuccesses)
        return tabSuccesses
    }

    @discardableResult
    func handleRefreshError(_ error: Error, settingGlobalError: Bool = true) async -> Bool {
        if case let CodeHostAuthError.rateLimited(retryAfter) = error {
            let delay = retryAfter ?? (15 * 60)
            rateLimitedUntil = Date().addingTimeInterval(delay)
            let minutes = Int((delay / 60).rounded(.up))
            appendDeveloperLog("GitHub rate limited, backing off for \(minutes)m")
            return true
        }
        guard let newState = Self.authState(afterRefreshError: error, signedInLogin: signedInLogin) else {
            if settingGlobalError {
                pullRequestRefreshError = error.localizedDescription
                appendDeveloperLog("Refresh failed: \(error.localizedDescription)")
            }
            return false
        }
        authState = newState
        if case .sessionExpired = newState {
            appendDeveloperLog("Refresh failed: session expired, showing re-auth prompt")
            stopPullRequestRefreshLoop()
        } else if case .signedOut = newState {
            try? await deleteStoredToken()
            appendDeveloperLog("Refresh failed: invalid credentials")
            stopPullRequestRefreshLoop()
        }
        return true
    }

    // MARK: - Private

    private func handleRestoreCredentialError(cachedLogin: String?) async {
        if let cachedLogin {
            authState = .sessionExpired(login: cachedLogin)
            appendDeveloperLog("Saved GitHub credentials were rejected, showing re-auth prompt")
        } else {
            try? await deleteStoredToken()
            authState = .signedOut
            appendDeveloperLog("Saved GitHub credentials were rejected")
        }
        stopPullRequestRefreshLoop()
    }

    private func handleRestoreGenericError(_ error: Error, cachedLogin: String?) {
        if let cachedLogin {
            useCachedLogin(cachedLogin)
            appendDeveloperLog(
                "Session restore failed, keeping cached login @\(cachedLogin): \(error.localizedDescription)"
            )
            startPullRequestRefreshLoop()
        } else {
            authState = .error(error.localizedDescription)
            appendDeveloperLog("Session restore failed: \(error.localizedDescription)")
            stopPullRequestRefreshLoop()
        }
    }

    private func startPullRequestRefreshLoop() {
        isRefreshLoopRunning = true
        scheduler.start(
            context: { [weak self] in
                guard let self else { return RefreshContext() }
                let isRateLimited = rateLimitedUntil.map { $0 > Date() } ?? false
                return RefreshContext(
                    isRateLimited: isRateLimited,
                    hasUrgentSLO: AttentionState.hasUrgentSLO(data: data, settings: settings),
                    isPopoverOpen: isPopoverOpen,
                    isAllGreen: AttentionState.isAllGreen(data: data)
                )
            },
            refresh: { [weak self] in
                await self?.refreshPullRequestsFromGitHub()
            }
        )
    }

    func stopPullRequestRefreshLoop() {
        isRefreshLoopRunning = false
        scheduler.stop()
        isRefreshingPullRequests = false
    }

    private func useCachedLogin(_ login: String) {
        authState = .signedIn(login: login)
        appendDeveloperLog("Using cached GitHub login @\(login)")
    }

    private func finishSignedInSession(login: String, name: String? = nil, avatarUrl: String? = nil) {
        authState = .signedIn(login: login)
        viewerName = name
        viewerAvatarURL = avatarUrl.flatMap { URL(string: $0) }
        appendDeveloperLog("Signed in as @\(login)")
        startPullRequestRefreshLoop()
        Task { await onSignedIn?() }
    }

    private func freshStoredToken() async throws -> StoredToken {
        guard var token = try await loadStoredToken() else {
            throw CodeHostAuthError.badCredentials
        }

        if !token.hasFreshAccessToken {
            token = try await authService.refresh(token)
            try await saveStoredToken(token)
        }

        return token
    }

    private var tokenStoreDescription: String {
        #if DEBUG
            return "development file for \(id.slug)"
        #else
            return "Keychain account \(id.slug)"
        #endif
    }

    private func loadStoredToken() async throws -> StoredToken? {
        let tokenStore = tokenStore
        return try await Task.detached(priority: .utility) {
            try tokenStore.load()
        }.value
    }

    private func saveStoredToken(_ token: StoredToken) async throws {
        let tokenStore = tokenStore
        try await Task.detached(priority: .utility) {
            try tokenStore.save(token)
        }.value
    }

    func deleteStoredToken() async throws {
        let tokenStore = tokenStore
        try await Task.detached(priority: .utility) {
            try tokenStore.delete()
        }.value
    }

}

extension Connection {
    var usernameDisplay: String {
        switch authState {
        case let .signedIn(login):
            "· @\(login)"
        case .waitingForUser:
            "· signing in"
        case .restoring:
            "· loading"
        case .signedOut:
            "· not signed in"
        case .sessionExpired:
            "· session expired"
        case .error:
            "· auth error"
        }
    }

    var canRefreshPullRequests: Bool {
        if case .signedIn = authState {
            return true
        }
        return false
    }

    var isAuthenticating: Bool {
        if case .waitingForUser = authState {
            return true
        }
        return false
    }

    var signedInLogin: String? {
        if case let .signedIn(login) = authState {
            return login
        }
        return nil
    }

    nonisolated static func authState(
        afterRefreshError error: Error,
        signedInLogin login: String?
    ) -> HubberAuthState? {
        switch error {
        case CodeHostAuthError.badCredentials, CodeHostAuthError.missingRefreshToken:
            if let login {
                .sessionExpired(login: login)
            } else {
                .signedOut
            }
        case is CancellationError:
            nil
        default:
            nil
        }
    }

    func clearDeveloperLog() {
        developerLog.removeAll()
    }

    func appendDeveloperLog(_ message: String) {
        CrashReporter.note(message)
        developerLog.insert(DeveloperLogEntry(timestamp: Date(), message: message), at: 0)
        if developerLog.count > 80 {
            developerLog.removeLast(developerLog.count - 80)
        }
    }

    var developerLogText: String {
        developerLog
            .map { entry in
                "[\(Self.developerLogFormatter.string(from: entry.timestamp))] \(entry.message)"
            }
            .joined(separator: "\n")
    }

    private static var developerLogFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}

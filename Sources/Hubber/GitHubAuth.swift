import AppKit
import Combine
import Foundation
import Security

// GitHub model types (GitHubDeviceAuthorization, GitHubStoredToken, GitHubAuthenticatedUser,
// GitHubAuthError) live in GitHub/GitHubModels.swift.

protocol GitHubTokenStoring: Sendable {
    func load() throws -> GitHubStoredToken?
    func save(_ token: GitHubStoredToken) throws
    func delete() throws
}

enum GitHubTokenStore {
    static func makeDefault() -> any GitHubTokenStoring {
        #if DEBUG
            return GitHubDevelopmentFileTokenStore()
        #else
            return GitHubKeychainTokenStore()
        #endif
    }
}

final class GitHubKeychainTokenStore: GitHubTokenStoring {
    private let service = "com.osuritz.hubber.github-auth"
    private let account = "github-app-user-token"

    func load() throws -> GitHubStoredToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw GitHubAuthError.keychain(status)
        }
        guard let data = item as? Data else {
            throw GitHubAuthError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubStoredToken.self, from: data)
    }

    func save(_ token: GitHubStoredToken) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(token)
        var query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw GitHubAuthError.keychain(status)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GitHubAuthError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubAuthError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

final class GitHubDevelopmentFileTokenStore: GitHubTokenStoring {
    private let tokenURL: URL

    init(tokenURL: URL = GitHubDevelopmentFileTokenStore.defaultTokenURL) {
        self.tokenURL = tokenURL
    }

    func load() throws -> GitHubStoredToken? {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: tokenURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubStoredToken.self, from: data)
    }

    func save(_ token: GitHubStoredToken) throws {
        try FileManager.default.createDirectory(
            at: tokenURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(token)
        try data.write(to: tokenURL, options: [.atomic])
    }

    func delete() throws {
        guard FileManager.default.fileExists(atPath: tokenURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: tokenURL)
    }

    static var defaultTokenURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseURL = appSupport
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL
            .appendingPathComponent("Hubber", isDirectory: true)
            .appendingPathComponent("github-auth-dev.json")
    }
}

// MARK: - GitHubAuthServicing protocol

//
// Extracted from GitHubAuthService to allow injection of test spies. The real implementation
// is GitHubAuthService; tests use a lightweight spy to verify call counts without hitting the
// network or requiring a bundle / keychain.

protocol GitHubAuthServicing: Sendable {
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization
    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> GitHubStoredToken
    func refresh(_ token: GitHubStoredToken) async throws -> GitHubStoredToken
    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser
}

final class GitHubAuthService: GitHubAuthServicing, Sendable {
    private let clientID: String
    private let session: URLSession

    init(clientID: String = GitHubAppConfig.clientID, session: URLSession = .shared) {
        self.clientID = clientID
        self.session = session
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        let response: DeviceCodeResponse = try await postForm(
            url: URL(string: "https://github.com/login/device/code")!,
            parameters: ["client_id": clientID]
        )

        guard let verificationURI = URL(string: response.verificationURI) else {
            throw GitHubAuthError.invalidResponse
        }

        return GitHubDeviceAuthorization(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURI: verificationURI,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            interval: response.interval
        )
    }

    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        var interval = max(deviceAuthorization.interval, 1)

        while !Task.isCancelled, !deviceAuthorization.isExpired {
            try await Task.sleep(for: .seconds(interval))

            let response: TokenResponse = try await postForm(
                url: URL(string: "https://github.com/login/oauth/access_token")!,
                parameters: [
                    "client_id": clientID,
                    "device_code": deviceAuthorization.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ]
            )

            if let token = response.storedToken() {
                return token
            }

            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval = response.interval ?? interval + 5
            case "expired_token", "token_expired":
                throw GitHubAuthError.authorizationExpired
            case "access_denied":
                throw GitHubAuthError.authorizationDenied
            case "device_flow_disabled":
                throw GitHubAuthError.deviceFlowDisabled
            case let .some(error):
                throw GitHubAuthError.github(response.errorDescription ?? error)
            case nil:
                throw GitHubAuthError.invalidResponse
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }
        throw GitHubAuthError.authorizationExpired
    }

    func refresh(_ token: GitHubStoredToken) async throws -> GitHubStoredToken {
        guard let refreshToken = token.refreshToken, token.canRefresh else {
            throw GitHubAuthError.missingRefreshToken
        }

        let response: TokenResponse = try await postForm(
            url: URL(string: "https://github.com/login/oauth/access_token")!,
            parameters: [
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ]
        )

        if var refreshed = response.storedToken() {
            refreshed.login = token.login
            return refreshed
        }

        if response.error == "bad_refresh_token" {
            throw GitHubAuthError.missingRefreshToken
        }
        let fallback = "GitHub could not refresh the token."
        throw GitHubAuthError.github(response.errorDescription ?? response.error ?? fallback)
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAuthError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw GitHubAuthError.badCredentials
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubAuthError.github("GitHub returned HTTP \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(GitHubAuthenticatedUser.self, from: data)
    }

    private func postForm<T: Decodable>(url: URL, parameters: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.formURLEncoded().data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubAuthError.github("GitHub returned HTTP \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class HubberStore: ObservableObject {
    @Published var authState: HubberAuthState = .restoring
    @Published private(set) var viewerName: String?
    @Published private(set) var viewerAvatarURL: URL?
    @Published var data = HubberData.sample
    @Published private(set) var isRefreshingPullRequests = false
    @Published private(set) var lastPullRequestRefresh: Date?
    @Published var pullRequestRefreshError: String?
    /// Per-tab fetch errors. Nil when the last fetch for that tab succeeded.
    @Published var incomingError: String?
    @Published var outgoingError: String?
    @Published var draftsError: String?
    @Published private(set) var developerLog: [DeveloperLogEntry] = []
    @Published private(set) var isPopoverOpen = false
    /// True when the user has denied notification authorization.
    @Published internal(set) var notificationsDenied = false

    var rateLimitMessage: String? {
        guard let until = rateLimitedUntil, until > Date() else { return nil }
        return ReviewSLOPresentation.rateLimitFooter(secondsRemaining: until.timeIntervalSinceNow)
    }

    let settings: SettingsStore // exposed so views can bind
    let telemetry: Telemetry // exposed so views can emit events

    private let authService: any GitHubAuthServicing
    let provider: any CodeHostProvider
    private let tokenStore: any GitHubTokenStoring
    private let scheduler: RefreshScheduler
    private var authTask: Task<Void, Never>?
    @Published var rateLimitedUntil: Date?

    // MARK: - Notification pipeline

    let notificationCoordinator: NotificationCoordinator
    let snapshotStore: SnapshotStore
    /// Persisted baseline; nil on first run (initial load must not fire).
    var notificationBaseline: ReviewSnapshot?
    private let dispatcher: any NotificationDispatching

    init(
        authService: any GitHubAuthServicing = GitHubAuthService(),
        provider: any CodeHostProvider = CachingCodeHostProvider(wrapping: GitHubProvider()),
        tokenStore: any GitHubTokenStoring = GitHubTokenStore.makeDefault(),
        settings: SettingsStore = SettingsStore(),
        idle: any MachineIdleProviding = SystemIdleProvider(),
        telemetry: Telemetry = Telemetry(sink: TelemetryDeckSink()),
        dispatcher: any NotificationDispatching = UNNotificationDispatcher(),
        snapshotStore: SnapshotStore = SnapshotStore()
    ) {
        self.authService = authService
        self.provider = provider
        self.tokenStore = tokenStore
        self.settings = settings
        self.telemetry = telemetry
        self.snapshotStore = snapshotStore
        self.dispatcher = dispatcher
        notificationCoordinator = NotificationCoordinator(dispatcher: dispatcher)
        scheduler = RefreshScheduler(idle: idle)
        notificationBaseline = snapshotStore.load()
        restoreSession()
    }

    /// Sends a test notification through the real dispatcher.
    /// Surfaces the macOS permission prompt on first run and updates `notificationsDenied`.
    func sendTestNotification() async {
        let authorized = await dispatcher.ensureAuthorized()
        notificationsDenied = dispatcher.notificationsDenied
        guard authorized else {
            appendDeveloperLog("Sent test notification (authorized=false)")
            return
        }
        await dispatcher.post(NotificationContent(
            id: "hubber-test-notification",
            title: "Hubber",
            body: "Test notification — notifications are working.",
            url: nil
        ))
        appendDeveloperLog("Sent test notification (authorized=true)")
    }

    /// Requests macOS notification authorization at login. `ensureAuthorized()` is idempotent —
    /// it surfaces the system prompt only the first time and is a no-op once the user has decided.
    func requestNotificationAuthorization() async {
        _ = await dispatcher.ensureAuthorized()
        notificationsDenied = dispatcher.notificationsDenied
    }

    func setPopoverOpen(_ open: Bool) {
        isPopoverOpen = open
    }

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

    /// True while the GitHub device-flow sign-in is awaiting user authorization.
    /// The menu panel stays pinned open in this state so the user can read/copy the
    /// device code and switch to the browser without the panel closing on them.
    var isAuthenticating: Bool {
        if case .waitingForUser = authState {
            return true
        }
        return false
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

                let user: GitHubAuthenticatedUser
                do {
                    user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
                } catch GitHubAuthError.badCredentials where token.canRefresh {
                    token = try await authService.refresh(token)
                    user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
                }

                token.login = user.login
                try await saveStoredToken(token)
                finishSignedInSession(login: user.login, name: user.name, avatarUrl: user.avatarUrl)
            } catch GitHubAuthError.badCredentials, GitHubAuthError.missingRefreshToken {
                await handleRestoreCredentialError(cachedLogin: cachedLogin)
            } catch {
                await handleRestoreGenericError(error, cachedLogin: cachedLogin)
            }
        }
    }

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

    func startSignIn() {
        // Defense in depth (#54): refuse before starting the device flow when the provider
        // policy blocks github.com. The UI also disables the button, but enforcing here
        // prevents any code path from bypassing the restriction.
        let policy = settings.providerAccessPolicy
        guard policy.canConnectGitHubDotCom else {
            let reason = policy.blockedReason ?? "Sign-in is restricted by your organization."
            appendDeveloperLog("Sign-in blocked by policy: \(reason)")
            authTask?.cancel()
            authTask = nil // prevent session-restore from overwriting error
            authState = .error(reason)
            return
        }

        appendDeveloperLog("Starting GitHub device sign-in")
        authTask?.cancel()
        authTask = Task {
            do {
                authState = .restoring
                let deviceAuthorization = try await authService.startDeviceFlow()
                authState = .waitingForUser(deviceAuthorization)
                appendDeveloperLog("Waiting for GitHub device authorization")

                var token = try await authService.pollForToken(deviceAuthorization: deviceAuthorization)
                let user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
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

    func cancelSignIn() {
        authTask?.cancel()
        authTask = nil
        authState = .signedOut
        appendDeveloperLog("GitHub sign-in cancelled")
        stopPullRequestRefreshLoop()
    }

    func signOut() {
        appendDeveloperLog("Signing out")
        authTask?.cancel()
        stopPullRequestRefreshLoop()
        authTask = Task {
            do {
                if let invalidating = provider as? CodeHostCacheInvalidating {
                    await invalidating.invalidateAll()
                }
                try await deleteStoredToken()
                authState = .signedOut
                viewerName = nil
                viewerAvatarURL = nil
                data = HubberData.sample
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

    func refreshPullRequests() {
        guard canRefreshPullRequests, !isRefreshingPullRequests else {
            appendDeveloperLog("Ignored manual refresh request")
            return
        }

        appendDeveloperLog("Manual pull request refresh requested")
        telemetry.manualRefresh()
        scheduler.reset()
    }

    func clearDeveloperLog() {
        developerLog.removeAll()
    }

    func copyDeveloperLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(developerLogText, forType: .string)
    }

    private func startPullRequestRefreshLoop() {
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
        // Ask for notification permission at login (idempotent — prompts only the first time)
        // rather than lazily at the first diff event, so the ask happens at a predictable moment.
        Task { await requestNotificationAuthorization() }
    }

    func stopPullRequestRefreshLoop() {
        scheduler.stop()
        isRefreshingPullRequests = false
    }

    private func refreshPullRequestsFromGitHub() async {
        guard canRefreshPullRequests, !isRefreshingPullRequests else { return }
        guard rateLimitedUntil.map({ $0 > Date() }) != true else {
            let until = rateLimitedUntil.map { Self.developerLogFormatter.string(from: $0) } ?? "unknown"
            appendDeveloperLog("Skipped refresh: rate-limited until \(until)")
            return
        }
        guard let login = signedInLogin else {
            appendDeveloperLog("Skipped refresh: no signed-in login")
            return
        }

        isRefreshingPullRequests = true
        defer { isRefreshingPullRequests = false }

        // Obtain a fresh token — a token error is a global (credential) failure.
        let token: GitHubStoredToken
        do {
            token = try await freshStoredToken()
        } catch is CancellationError {
            appendDeveloperLog("Pull request refresh cancelled")
            return
        } catch {
            await handleRefreshError(error)
            return
        }

        appendDeveloperLog("Refreshing all tabs for @\(login)")
        let (didStop, tabSuccesses) = await fetchAllTabsIndependently(token: token, login: login)
        if !didStop {
            lastPullRequestRefresh = Date()
            pullRequestRefreshError = nil
            rateLimitedUntil = nil
            let counts = "\(data.incoming.count) incoming, \(data.outgoing.count) outgoing, \(data.drafts.count) drafts"
            appendDeveloperLog("Fetched \(counts)")
            await dispatchNotifications(tabSuccesses: tabSuccesses)
        }
    }

    private func freshStoredToken() async throws -> GitHubStoredToken {
        guard var token = try await loadStoredToken() else {
            throw GitHubAuthError.badCredentials
        }

        if !token.hasFreshAccessToken {
            token = try await authService.refresh(token)
            try await saveStoredToken(token)
        }

        return token
    }

    var signedInLogin: String? {
        if case let .signedIn(login) = authState {
            return login
        }
        return nil
    }

    /// Maps a refresh error to the resulting `HubberAuthState` (or `nil` to leave state unchanged).
    nonisolated static func authState(
        afterRefreshError error: Error,
        signedInLogin login: String?
    ) -> HubberAuthState? {
        switch error {
        case GitHubAuthError.badCredentials, GitHubAuthError.missingRefreshToken:
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

    private var developerLogText: String {
        developerLog
            .map { entry in
                "[\(Self.developerLogFormatter.string(from: entry.timestamp))] \(entry.message)"
            }
            .joined(separator: "\n")
    }

    func appendDeveloperLog(_ message: String) {
        developerLog.insert(DeveloperLogEntry(timestamp: Date(), message: message), at: 0)
        if developerLog.count > 80 {
            developerLog.removeLast(developerLog.count - 80)
        }
    }

    private static let developerLogFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var tokenStoreDescription: String {
        #if DEBUG
            return "development file at \(GitHubDevelopmentFileTokenStore.defaultTokenURL.path)"
        #else
            return "Keychain"
        #endif
    }

    private func loadStoredToken() async throws -> GitHubStoredToken? {
        let tokenStore = tokenStore
        return try await Task.detached(priority: .utility) {
            try tokenStore.load()
        }.value
    }

    private func saveStoredToken(_ token: GitHubStoredToken) async throws {
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

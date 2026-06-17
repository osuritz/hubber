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
    static let legacyAccount = "github-app-user-token"

    private let service = "com.osuritz.hubber.github-auth"
    private let account: String

    init(account: String = GitHubKeychainTokenStore.legacyAccount) {
        self.account = account
    }

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

}

// MARK: - Auth service seams

//
// Extracted from GitHubAuthService to allow injection of test spies. The real implementation is
// GitHubAuthService; tests use a lightweight spy to verify call counts without hitting the network
// or requiring a bundle / keychain.

/// Generic code-host authentication seam. The GitLab PAT credential path will be added here in #60.
protocol CodeHostAuthServicing: Sendable {
    func refresh(_ token: GitHubStoredToken) async throws -> GitHubStoredToken
    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser
}

protocol GitHubDeviceFlowServicing: CodeHostAuthServicing {
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization
    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> GitHubStoredToken
}

typealias GitHubAuthServicing = GitHubDeviceFlowServicing

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

    // MARK: - Coordinator: connection list

    /// Insertion-ordered, never reordered. `primaryConnection` is always `connections.first`.
    @Published private(set) var connections: [Connection] = []

    var primaryConnection: Connection? {
        connections.first
    }

    // MARK: - Aggregated published state

    /// Aggregated across all connections. Also directly settable for backward-compat with
    /// NotificationWiringTests (which sets store.data directly). Recomputed via sink on
    /// any connection change (Task 7 / R1).
    @Published var data = HubberData(incoming: [], outgoing: [], drafts: [])
    @Published private(set) var isRefreshingPullRequests = false
    @Published private(set) var isPopoverOpen = false
    /// True when the user has denied notification authorization.
    @Published var notificationsDenied = false

    // MARK: - Single-connection surface forwarded from primaryConnection

    var authState: HubberAuthState {
        get { primaryConnection?.authState ?? .signedOut }
        set {
            primaryConnection?.authState = newValue
            recomputeAggregate()
        }
    }

    var viewerName: String? {
        primaryConnection?.viewerName
    }

    var viewerAvatarURL: URL? {
        primaryConnection?.viewerAvatarURL
    }

    var lastPullRequestRefresh: Date? {
        primaryConnection?.lastPullRequestRefresh
    }

    var developerLog: [DeveloperLogEntry] {
        primaryConnection?.developerLog ?? []
    }

    var pullRequestRefreshError: String? {
        get { primaryConnection?.pullRequestRefreshError }
        set { primaryConnection?.pullRequestRefreshError = newValue }
    }

    var incomingError: String? {
        get { primaryConnection?.incomingError }
        set { primaryConnection?.incomingError = newValue }
    }

    var outgoingError: String? {
        get { primaryConnection?.outgoingError }
        set { primaryConnection?.outgoingError = newValue }
    }

    var draftsError: String? {
        get { primaryConnection?.draftsError }
        set { primaryConnection?.draftsError = newValue }
    }

    var rateLimitedUntil: Date? {
        get { primaryConnection?.rateLimitedUntil }
        set { primaryConnection?.rateLimitedUntil = newValue }
    }

    var rateLimitMessage: String? {
        guard let until = rateLimitedUntil, until > Date() else { return nil }
        return ReviewSLOPresentation.rateLimitFooter(secondsRemaining: until.timeIntervalSinceNow)
    }

    let settings: SettingsStore // exposed so views can bind
    let telemetry: Telemetry // exposed so views can emit events
    var provider: any CodeHostProvider {
        primaryConnection?.provider ?? CachingCodeHostProvider(wrapping: GitHubProvider())
    }

    // MARK: - Notification pipeline

    let notificationCoordinator: NotificationCoordinator
    /// The legacy connection's snapshot store (also used for `restoreSession` legacy path).
    /// Baselines are now owned exclusively by each `Connection` (C2: single source of truth).
    let snapshotStore: SnapshotStore
    private let dispatcher: any NotificationDispatching
    private let registry: ConnectionRegistry
    private var cancellables = Set<AnyCancellable>()
    /// Separate bag cleared on every rebind so removed connections are unsubscribed.
    private var connectionCancellables = Set<AnyCancellable>()

    // Dependencies stored for building legacy connection
    private let legacyAuthService: any GitHubAuthServicing
    private let legacyProvider: any CodeHostProvider
    private let legacyTokenStore: any GitHubTokenStoring
    private let legacyIdle: any MachineIdleProviding
    /// Optional factory used by tests to supply pre-built `Connection` objects during
    /// `restoreAllConnections()`. When `nil`, the store builds connections from injected
    /// legacy deps (single-connection path).
    private let connectionFactory: ((ConnectionID) throws -> Connection)?

    init(
        authService: any GitHubAuthServicing = GitHubAuthService(),
        provider: any CodeHostProvider = CachingCodeHostProvider(wrapping: GitHubProvider()),
        tokenStore: any GitHubTokenStoring = GitHubTokenStore.makeDefault(),
        settings: SettingsStore = SettingsStore(),
        idle: any MachineIdleProviding = SystemIdleProvider(),
        telemetry: Telemetry = Telemetry(sink: TelemetryDeckSink()),
        dispatcher: any NotificationDispatching = UNNotificationDispatcher(),
        snapshotStore: SnapshotStore = SnapshotStore(),
        defaults: UserDefaults = .standard,
        restoreOnInit: Bool = true,
        connectionFactory: ((ConnectionID) throws -> Connection)? = nil
    ) {
        self.settings = settings
        self.telemetry = telemetry
        self.snapshotStore = snapshotStore
        self.dispatcher = dispatcher
        legacyAuthService = authService
        legacyProvider = provider
        legacyTokenStore = tokenStore
        legacyIdle = idle
        self.connectionFactory = connectionFactory
        notificationCoordinator = NotificationCoordinator(dispatcher: dispatcher)
        registry = ConnectionRegistry(defaults: defaults)

        if restoreOnInit {
            restoreSession()
        }
    }

    // MARK: - Legacy single-connection restore (used by restoreOnInit path)

    private func buildLegacyConnection() -> Connection {
        let conn = Connection(
            id: .gitHubDotCom(login: "legacy"),
            provider: legacyProvider,
            authService: legacyAuthService,
            tokenStore: legacyTokenStore,
            snapshotStore: snapshotStore,
            scheduler: RefreshScheduler(idle: legacyIdle),
            settings: settings
        )
        // Connection.init already seeds notificationBaseline from its snapshotStore.load().
        wireCallbacks(on: conn)
        return conn
    }

    private func wireCallbacks(on conn: Connection) {
        conn.onRefreshSucceeded = { [weak self, weak conn] tabSuccesses in
            guard let self else { return }
            recomputeAggregate()
            await handleRefreshSucceeded(conn, tabSuccesses)
        }
        conn.onSignedIn = { [weak self] in
            await self?.requestNotificationAuthorization()
        }
    }

    // MARK: - Coordinator: add / remove / restore

    /// Builds a new `Connection` with injected or default dependencies and appends it.
    /// - Parameters:
    ///   - id: The `ConnectionID` that identifies this connection (and keys its stores).
    ///   - provider: Optional provider override (for tests). Defaults to the store's legacy provider.
    ///   - authService: Optional auth-service override. Defaults to the store's legacy auth service.
    ///   - tokenStore: Optional token-store override. Defaults to a `GitHubTokenStore.makeStore(for:id)`.
    ///   - snapshotStore: Optional snapshot-store override. Defaults to `SnapshotStore(connectionID:id)`.
    ///   - scheduler: Optional scheduler override. Defaults to a fresh `RefreshScheduler`.
    @discardableResult
    func addConnection(
        id: ConnectionID,
        provider: (any CodeHostProvider)? = nil,
        authService: (any GitHubAuthServicing)? = nil,
        tokenStore: (any GitHubTokenStoring)? = nil,
        snapshotStore: SnapshotStore? = nil,
        scheduler: RefreshScheduler? = nil
    ) throws -> Connection {
        let resolvedProvider = provider ?? legacyProvider
        let resolvedAuthService = authService ?? legacyAuthService
        let resolvedTokenStore = tokenStore ?? GitHubTokenStore.makeStore(for: id)
        let resolvedSnapshotStore = snapshotStore ?? SnapshotStore(connectionID: id)
        let resolvedScheduler = scheduler ?? RefreshScheduler(idle: legacyIdle)

        let conn = Connection(
            id: id,
            provider: resolvedProvider,
            authService: resolvedAuthService,
            tokenStore: resolvedTokenStore,
            snapshotStore: resolvedSnapshotStore,
            scheduler: resolvedScheduler,
            settings: settings
        )
        wireCallbacks(on: conn)
        connections.append(conn)
        rebindConnections()
        try registry.append(id)
        return conn
    }

    /// Removes a specific connection: signs it out, deletes its snapshot, prunes registry.
    func removeConnection(_ id: ConnectionID) async {
        guard let index = connections.firstIndex(where: { $0.id == id }) else { return }
        let conn = connections[index]
        await conn.signOut()
        conn.snapshotStore.delete()
        connections.remove(at: index)
        rebindConnections()
        try? registry.remove(id)
    }

    /// Signs out ALL connections and clears the registry.
    func signOut() async {
        for conn in connections {
            await conn.signOut()
            conn.snapshotStore.delete()
        }
        connections.removeAll()
        rebindConnections()
        registry.removeAll()
    }

    /// Restores connections from the registry. If the registry is empty, falls back to
    /// the legacy single-connection path (including migration from the legacy token/snapshot).
    func restoreAllConnections() {
        let ids = registry.load()
        if ids.isEmpty {
            // Legacy single-connection path: build and restore one connection
            let conn = buildLegacyConnection()
            connections = [conn]
            rebindConnections()
            conn.restoreSession()
        } else {
            // Multi-connection path: build a Connection per registered id
            var built: [Connection] = []
            for id in ids {
                let conn: Connection
                if let factory = connectionFactory {
                    guard let c = try? factory(id) else { continue }
                    conn = c
                } else {
                    conn = Connection(
                        id: id,
                        provider: legacyProvider,
                        authService: legacyAuthService,
                        tokenStore: GitHubTokenStore.makeStore(for: id),
                        snapshotStore: SnapshotStore(connectionID: id),
                        scheduler: RefreshScheduler(idle: legacyIdle),
                        settings: settings
                    )
                }
                wireCallbacks(on: conn)
                built.append(conn)
            }
            connections = built
            rebindConnections()
            for conn in connections {
                conn.restoreSession()
            }
        }
    }

    // MARK: - Aggregate recomputation (R1/R2)

    private func rebindConnections() {
        connectionCancellables.removeAll()
        Publishers.MergeMany(connections.map(\.objectWillChange))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recomputeAggregate() }
            .store(in: &connectionCancellables)
        recomputeAggregate()
    }

    private func recomputeAggregate() {
        data = ConnectionAggregator.aggregate(connections.map(\.data))
        isRefreshingPullRequests = connections.contains { $0.isRefreshingPullRequests }
    }

    // MARK: - Legacy restoreSession (used by existing tests via restoreOnInit path)

    func restoreSession() {
        let conn = buildLegacyConnection()
        connections = [conn]
        rebindConnections()
        conn.restoreSession()
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
        primaryConnection?.isPopoverOpen = open
    }

    var usernameDisplay: String {
        primaryConnection?.usernameDisplay ?? "· not signed in"
    }

    var canRefreshPullRequests: Bool {
        primaryConnection?.canRefreshPullRequests ?? false
    }

    /// True while the GitHub device-flow sign-in is awaiting user authorization.
    /// The menu panel stays pinned open in this state so the user can read/copy the
    /// device code and switch to the browser without the panel closing on them.
    var isAuthenticating: Bool {
        primaryConnection?.isAuthenticating ?? false
    }

    func startSignIn() {
        startSignIn(policy: settings.providerAccessPolicy)
    }

    func startSignIn(policy: ProviderAccessPolicy) {
        let connection: Connection
        if let existing = primaryConnection {
            connection = existing
        } else {
            // After signOut() the connection list is empty — rebuild a fresh legacy
            // connection so the user can sign back in.
            connection = buildLegacyConnection()
            connections = [connection]
            rebindConnections()
        }
        connection.startSignIn(policy: policy)
    }

    func cancelSignIn() {
        primaryConnection?.cancelSignIn()
    }

    func openDeviceVerificationPage() {
        primaryConnection?.openDeviceVerificationPage()
    }

    func copyDeviceCode() {
        primaryConnection?.copyDeviceCode()
    }

    func refreshPullRequests() {
        guard canRefreshPullRequests, !isRefreshingPullRequests else {
            appendDeveloperLog("Ignored manual refresh request")
            return
        }

        appendDeveloperLog("Manual pull request refresh requested")
        telemetry.manualRefresh()
        primaryConnection?.refreshNow()
    }

    func clearDeveloperLog() {
        primaryConnection?.clearDeveloperLog()
    }

    func copyDeveloperLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primaryConnection?.developerLogText ?? "", forType: .string)
    }

    var signedInLogin: String? {
        primaryConnection?.signedInLogin
    }

    /// Maps a refresh error to the resulting `HubberAuthState` (or `nil` to leave state unchanged).
    nonisolated static func authState(
        afterRefreshError error: Error,
        signedInLogin login: String?
    ) -> HubberAuthState? {
        Connection.authState(afterRefreshError: error, signedInLogin: login)
    }

    func appendDeveloperLog(_ message: String) {
        primaryConnection?.appendDeveloperLog(message)
    }
}

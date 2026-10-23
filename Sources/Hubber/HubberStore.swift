import AppKit
import Combine
import Foundation

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

    let settings: SettingsStore // exposed so views can bind
    let telemetry: Telemetry // exposed so views can emit events
    var provider: any CodeHostProvider {
        primaryConnection?.provider ?? fallbackProvider
    }

    // MARK: - Notification pipeline

    let notificationCoordinator: NotificationCoordinator
    /// Serializes notification passes across refresh schedulers. Internal for the split notification extension.
    var notificationTail: Task<Void, Never> = Task {}
    /// The legacy connection's snapshot store (also used for `restoreSession` legacy path).
    /// Baselines are now owned exclusively by each `Connection` (C2: single source of truth).
    let snapshotStore: SnapshotStore
    private let dispatcher: any NotificationDispatching
    private let registry: ConnectionRegistry
    private var cancellables = Set<AnyCancellable>()
    /// Separate bag cleared on every rebind so removed connections are unsubscribed.
    private var connectionCancellables = Set<AnyCancellable>()
    private var restorePrunableConnectionIDs = Set<ConnectionID>()
    private let fallbackProvider: any CodeHostProvider
    /// Live analytics gate when telemetry is not injected (production path); nil when a
    /// caller injects its own Telemetry (tests). Subscribed to `settings.$analyticsEnabled`.
    private let telemetryGate: GatedTelemetrySink?

    // Dependencies stored for building legacy connection
    private let legacyAuthService: any GitHubAuthServicing
    private let legacyProvider: any CodeHostProvider
    private let legacyTokenStore: any TokenStoring
    private let legacyIdle: any MachineIdleProviding
    private let connectionFactory: ((ConnectionID) throws -> Connection)?
    private let launchAtLogin: any LaunchAtLoginManaging

    init(
        authService: any GitHubAuthServicing = GitHubAuthService(),
        provider: any CodeHostProvider = CachingCodeHostProvider(wrapping: GitHubProvider()),
        tokenStore: any TokenStoring = TokenStore.makeDefault(),
        settings: SettingsStore = SettingsStore(),
        idle: any MachineIdleProviding = SystemIdleProvider(),
        telemetry: Telemetry? = nil,
        telemetryGate injectedGate: GatedTelemetrySink? = nil,
        dispatcher: any NotificationDispatching = UNNotificationDispatcher(),
        snapshotStore: SnapshotStore = SnapshotStore(),
        defaults: UserDefaults = .standard,
        restoreOnInit: Bool = true,
        connectionFactory: ((ConnectionID) throws -> Connection)? = nil,
        launchAtLogin: any LaunchAtLoginManaging = SMAppServiceLaunchAtLogin()
    ) {
        self.settings = settings
        self.launchAtLogin = launchAtLogin
        if let telemetry {
            self.telemetry = telemetry
            telemetryGate = nil
        } else {
            let gate = injectedGate
                ?? GatedTelemetrySink(enabled: settings.analyticsEnabled, underlying: TelemetryDeckSink())
            self.telemetry = Telemetry(sink: gate)
            telemetryGate = gate
        }
        self.snapshotStore = snapshotStore
        self.dispatcher = dispatcher
        fallbackProvider = CachingCodeHostProvider(wrapping: GitHubProvider())
        legacyAuthService = authService
        legacyProvider = provider
        legacyTokenStore = tokenStore
        legacyIdle = idle
        self.connectionFactory = connectionFactory
        notificationCoordinator = NotificationCoordinator(dispatcher: dispatcher)
        registry = ConnectionRegistry(defaults: defaults)

        if let telemetryGate {
            settings.$analyticsEnabled
                .sink { [weak telemetryGate] enabled in telemetryGate?.setEnabled(enabled) }
                .store(in: &cancellables)
        }

        // Re-publish when the nested SettingsStore changes so views observing this
        // store (e.g. the popover header badges reading settings.tabBadgeMode) refresh
        // live instead of waiting for an unrelated invalidation.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

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
            // During first-run onboarding, the notification priming step (#107) owns the OS
            // permission prompt — requesting here on connect would surface the system dialog
            // before the soft pre-prompt. Skip until onboarding completes; afterwards keep
            // M3's request-at-login behavior for re-sign-ins.
            guard OnboardingCoordinator.isCompleted() else { return }
            await self?.requestNotificationAuthorization()
        }
    }

    // MARK: - Coordinator: add / remove / restore

    @discardableResult
    func addConnection(
        id: ConnectionID,
        provider: (any CodeHostProvider)? = nil,
        authService: (any GitHubDeviceFlowServicing)? = nil,
        tokenStore: (any TokenStoring)? = nil,
        snapshotStore: SnapshotStore? = nil,
        scheduler: RefreshScheduler? = nil
    ) throws -> Connection {
        if let existing = connections.first(where: { $0.id == id }) {
            return existing
        }

        let conn: Connection
        if
            provider == nil,
            authService == nil,
            tokenStore == nil,
            snapshotStore == nil,
            scheduler == nil,
            let connectionFactory {
            conn = try connectionFactory(id)
        } else {
            let factoryBuilt = ConnectionFactory.providerAndAuth(for: id)
            let resolvedProvider = provider ?? factoryBuilt.provider
            let resolvedAuthService = authService ?? factoryBuilt.authService
            let resolvedTokenStore = tokenStore ?? TokenStore.makeStore(for: id)
            let resolvedSnapshotStore = snapshotStore ?? SnapshotStore(connectionID: id)
            let resolvedScheduler = scheduler ?? RefreshScheduler(idle: legacyIdle)

            conn = Connection(
                id: id,
                provider: resolvedProvider,
                authService: resolvedAuthService,
                tokenStore: resolvedTokenStore,
                snapshotStore: resolvedSnapshotStore,
                scheduler: resolvedScheduler,
                settings: settings
            )
        }
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
        guard !conn.authState.isError else {
            rebindConnections()
            return
        }
        conn.snapshotStore.delete()
        connections.remove(at: index)
        rebindConnections()
        try? registry.remove(id)
    }

    /// Signs out ALL connections and removes cleanly signed-out entries from the registry.
    func signOut() async {
        var remainingConnections: [Connection] = []
        for conn in connections {
            await conn.signOut()
            guard !conn.authState.isError else {
                remainingConnections.append(conn)
                continue
            }
            conn.snapshotStore.delete()
            try? registry.remove(conn.id)
        }
        connections = remainingConnections
        rebindConnections()
    }

    /// Restores connections from the registry. If the registry is empty, falls back to
    /// the legacy single-connection path (including migration from the legacy token/snapshot).
    func restoreAllConnections() {
        let ids = registry.load()
        if ids.isEmpty {
            restorePrunableConnectionIDs.removeAll()
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
                    let resolved = ConnectionFactory.providerAndAuth(for: id)
                    conn = Connection(
                        id: id,
                        provider: resolved.provider,
                        authService: resolved.authService,
                        tokenStore: TokenStore.makeStore(for: id),
                        snapshotStore: SnapshotStore(connectionID: id),
                        scheduler: RefreshScheduler(idle: legacyIdle),
                        settings: settings
                    )
                }
                wireCallbacks(on: conn)
                built.append(conn)
            }
            restorePrunableConnectionIDs = Set(built.map(\.id))
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
            .sink { [weak self] _ in
                guard let self else { return }
                // Forwarded primary-connection properties such as `authState` are not @Published on
                // this store, so their popover refresh depends on this explicit emission.
                objectWillChange.send()
                recomputeAggregate()
                pruneSignedOutGhosts()
            }
            .store(in: &connectionCancellables)
        recomputeAggregate()
    }

    private func recomputeAggregate() {
        data = ConnectionAggregator.aggregate(
            connections.map { (id: $0.id, data: $0.data) },
            visibility: settings.connectionVisibility
        )
        isRefreshingPullRequests = connections.contains { $0.isRefreshingPullRequests }
    }

    private func pruneSignedOutGhosts() {
        let registeredIDs = Set(registry.load())
        var settledIDs: [ConnectionID] = []
        let ghostIDs = connections.compactMap { conn -> ConnectionID? in
            guard restorePrunableConnectionIDs.contains(conn.id), conn.authState != .restoring else {
                return nil
            }
            settledIDs.append(conn.id)
            guard registeredIDs.contains(conn.id), conn.authState == .signedOut, (try? conn.tokenStore.load()) == nil else {
                return nil
            }
            return conn.id
        }

        restorePrunableConnectionIDs.subtract(settledIDs)
        guard !ghostIDs.isEmpty else { return }

        let ghosts = Set(ghostIDs)
        connections.removeAll { ghosts.contains($0.id) }
        for id in ghostIDs {
            try? registry.remove(id)
        }
        rebindConnections()
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

    /// Sets the launch-at-login preference: persists the desired state and applies it to the system.
    func setLaunchAtLogin(_ enabled: Bool) {
        // A user action must not override an MDM-forced value.
        guard !settings.isLocked(ManagedKey.launchAtLogin) else { return }
        try? launchAtLogin.setEnabled(enabled)
        // Persist the ACTUAL resulting state (not the intent), so the toggle can't lie if
        // registration failed or the login item changed outside the app.
        settings.launchAtLoginEnabled = launchAtLogin.isEnabled
    }

    /// Applies the resolved (incl. MDM-forced) desired launch-at-login state to the system at launch.
    func reconcileLaunchAtLogin() {
        try? launchAtLogin.setEnabled(settings.launchAtLoginEnabled)
    }

    func setPopoverOpen(_ open: Bool) {
        isPopoverOpen = open
        connections.forEach { $0.isPopoverOpen = open }
    }

    /// Shows or hides a connection in the unified inbox + badge. Persisted via SettingsStore.
    func setConnectionVisible(_ id: ConnectionID, _ visible: Bool) {
        settings.connectionVisibility = settings.connectionVisibility.setting(id, visible: visible)
        recomputeAggregate()
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

    /// True while the add-account sheet is open (any provider/step). Like `isAuthenticating`, this
    /// pins the popover so hopping to the browser — authorizing a device code, or following the
    /// "create a token" link — doesn't dismiss the in-progress add flow. Set by `AddAccountView`'s
    /// lifecycle. (The add-account device flow runs via a standalone auth service, not a
    /// `Connection`, so `isAuthenticating` alone never covers it.)
    /// `shouldPinPanel` + `addResolvedAccount` live in the `HubberStore+AddAccount` extension; this
    /// stored property and its setter stay here because `private(set)` is file-scoped.
    @Published private(set) var isAddingAccount = false

    func setAddingAccount(_ active: Bool) {
        isAddingAccount = active
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

// MARK: - Single-connection surface forwarded from primaryConnection

extension HubberStore {
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
}

private extension HubberAuthState {
    var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }
}

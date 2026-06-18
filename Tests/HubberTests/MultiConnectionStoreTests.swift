import Foundation
import XCTest
@testable import Hubber

// MARK: - Multi-connection test doubles

private final class MultiConnectionAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let login: String
    private let fetchUserResult: Result<GitHubAuthenticatedUser, Error>?
    private var _startDeviceFlowCallCount = 0

    var startDeviceFlowCallCount: Int {
        lock.withLock { _startDeviceFlowCallCount }
    }

    init(login: String, fetchUserResult: Result<GitHubAuthenticatedUser, Error>? = nil) {
        self.login = login
        self.fetchUserResult = fetchUserResult
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        lock.withLock { _startDeviceFlowCallCount += 1 }
        guard let verificationURI = URL(string: "https://github.com/login/device") else {
            throw GitHubAuthError.invalidResponse
        }
        return GitHubDeviceAuthorization(
            deviceCode: "device-\(login)",
            userCode: "USER-\(login)",
            verificationURI: verificationURI,
            expiresAt: Date().addingTimeInterval(600),
            interval: 1
        )
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        GitHubStoredToken(
            accessToken: "access-\(login)",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: login
        )
    }

    func refresh(_ token: GitHubStoredToken) async throws -> GitHubStoredToken {
        token
    }

    func fetchAuthenticatedUser(accessToken _: String) async throws -> GitHubAuthenticatedUser {
        if let fetchUserResult {
            return try fetchUserResult.get()
        }
        return GitHubAuthenticatedUser(login: login, name: nil, avatarUrl: nil)
    }
}

private final class MutableTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: GitHubStoredToken?
    private let deleteError: Error?

    init(token: GitHubStoredToken?, deleteError: Error? = nil) {
        self.token = token
        self.deleteError = deleteError
    }

    func load() throws -> GitHubStoredToken? {
        lock.withLock { token }
    }

    func save(_ token: GitHubStoredToken) throws {
        lock.withLock { self.token = token }
    }

    func delete() throws {
        if let deleteError {
            throw deleteError
        }
        lock.withLock { token = nil }
    }
}

private enum MultiConnectionTokenStoreError: LocalizedError {
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .deleteFailed:
            "Token delete failed"
        }
    }
}

private actor MultiConnectionProvider: CodeHostProvider {
    private let incomingResult: Result<[IncomingReview], Error>
    private let outgoingResult: Result<[OutgoingReview], Error>
    private let draftsResult: Result<[DraftReview], Error>

    init(
        incoming: Result<[IncomingReview], Error> = .success([]),
        outgoing: Result<[OutgoingReview], Error> = .success([]),
        drafts: Result<[DraftReview], Error> = .success([])
    ) {
        incomingResult = incoming
        outgoingResult = outgoing
        draftsResult = drafts
    }

    func fetchIncomingReviews(
        accessToken _: String,
        viewerLogin _: String,
        mode _: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        try incomingResult.get()
    }

    func fetchOutgoingPullRequests(
        accessToken _: String,
        viewerLogin _: String,
        unresolvedMode _: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        try outgoingResult.get()
    }

    func fetchDraftPullRequests(
        accessToken _: String,
        limit _: Int
    ) async throws -> [DraftReview] {
        try draftsResult.get()
    }
}

private actor InvalidatingMultiConnectionProvider: CodeHostProvider, CodeHostCacheInvalidating {
    private let wrapped: MultiConnectionProvider
    private(set) var invalidateAllCallCount = 0

    init(wrapped: MultiConnectionProvider = MultiConnectionProvider()) {
        self.wrapped = wrapped
    }

    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        try await wrapped.fetchIncomingReviews(accessToken: accessToken, viewerLogin: viewerLogin, mode: mode)
    }

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        try await wrapped.fetchOutgoingPullRequests(
            accessToken: accessToken,
            viewerLogin: viewerLogin,
            unresolvedMode: unresolvedMode
        )
    }

    func fetchDraftPullRequests(accessToken: String, limit: Int) async throws -> [DraftReview] {
        try await wrapped.fetchDraftPullRequests(accessToken: accessToken, limit: limit)
    }

    func invalidateAll() async {
        invalidateAllCallCount += 1
    }

    func invalidateCount() -> Int {
        invalidateAllCallCount
    }
}

private actor MultiConnectionSleeper {
    private(set) var requestedIntervals: [TimeInterval] = []
    private(set) var cancellationCount = 0
    private var parkWaiters: [CheckedContinuation<Void, Never>] = []
    private var sleeping: CheckedContinuation<Void, Error>?

    func sleep(for interval: TimeInterval) async throws {
        requestedIntervals.append(interval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sleeping = continuation
                for waiter in parkWaiters {
                    waiter.resume()
                }
                parkWaiters.removeAll()
            }
        } onCancel: {
            Task { await self.cancelSleep() }
        }
    }

    func awaitParked() async {
        await withCheckedContinuation { continuation in
            if sleeping != nil {
                continuation.resume()
            } else {
                parkWaiters.append(continuation)
            }
        }
    }

    var isSleeping: Bool {
        sleeping != nil
    }

    func cancellationSnapshot() -> Int {
        cancellationCount
    }

    func sleepingSnapshot() -> Bool {
        isSleeping
    }

    private func cancelSleep() {
        sleeping?.resume(throwing: CancellationError())
        sleeping = nil
        cancellationCount += 1
    }
}

private struct MultiConnectionIdleProvider: MachineIdleProviding {
    let isIdle = false
}

// MARK: - Tests

@MainActor
// swiftlint:disable:next type_body_length - growing multi-connection integration-test suite
final class MultiConnectionStoreTests: XCTestCase {
    func testSecondConnectionSignInDoesNotDisturbFirstConnection() async throws {
        let first = try makeConnection(login: "first")
        let second = try makeConnection(login: "second")

        first.authState = .signedIn(login: "first")

        second.startSignIn(policy: ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: []))
        try await waitForSignedIn(second, login: "second")

        XCTAssertEqual(first.authState, .signedIn(login: "first"))
        XCTAssertEqual(second.authState, .signedIn(login: "second"))
    }

    func testShouldPinPanelTracksAddingAccount() throws {
        // Regression: the add-account device flow runs via a standalone auth service (no Connection
        // enters .waitingForUser), so `isAuthenticating` never covers it. The popover must still
        // pin while the add-account sheet is open, or it closes when the browser opens for auth.
        let suite = "pin-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = makeStore(defaults: defaults, restoreOnInit: false)

        XCTAssertFalse(store.isAuthenticating) // no primary connection authenticating
        XCTAssertFalse(store.shouldPinPanel)

        store.setAddingAccount(true)
        XCTAssertTrue(store.shouldPinPanel) // pinned while adding, even with no authenticating connection

        store.setAddingAccount(false)
        XCTAssertFalse(store.shouldPinPanel)
    }

    func testRateLimitedConnectionDoesNotChangeOtherConnectionSchedulerCadence() async throws {
        let sleeperA = MultiConnectionSleeper()
        let sleeperB = MultiConnectionSleeper()
        let connectionA = try makeConnection(
            login: "limited",
            provider: MultiConnectionProvider(outgoing: .failure(GitHubAuthError.rateLimited(retryAfter: 120))),
            sleeper: sleeperA
        )
        let connectionB = try makeConnection(login: "healthy", sleeper: sleeperB)

        connectionA.authState = .signedIn(login: "limited")
        connectionB.authState = .signedIn(login: "healthy")

        connectionA.refreshNow()
        connectionB.refreshNow()
        await sleeperA.awaitParked()
        await sleeperB.awaitParked()

        let intervalsA = await sleeperA.requestedIntervals
        let intervalsB = await sleeperB.requestedIntervals
        let firstIntervalA = try XCTUnwrap(intervalsA.first)
        let firstIntervalB = try XCTUnwrap(intervalsB.first)
        XCTAssertEqual(firstIntervalA, TimeInterval(15 * 60), accuracy: 1)
        XCTAssertEqual(firstIntervalB, TimeInterval(5 * 60), accuracy: 1)
    }

    func testRateLimitedUntilIsSetOnlyOnFailingConnection() async throws {
        let connectionA = try makeConnection(
            login: "limited",
            provider: MultiConnectionProvider(outgoing: .failure(GitHubAuthError.rateLimited(retryAfter: 120)))
        )
        let connectionB = try makeConnection(login: "healthy")
        connectionA.authState = .signedIn(login: "limited")
        connectionB.authState = .signedIn(login: "healthy")

        _ = await connectionA.refreshPullRequestsFromGitHub()
        _ = await connectionB.refreshPullRequestsFromGitHub()

        XCTAssertNotNil(connectionA.rateLimitedUntil)
        XCTAssertNil(connectionB.rateLimitedUntil)
    }

    func testBlockedPolicyDoesNotStartDeviceFlowAndSetsError() async throws {
        let authService = MultiConnectionAuthService(login: "blocked")
        let connection = try makeConnection(login: "blocked", authService: authService)

        connection.startSignIn(policy: ProviderAccessPolicy(allowPersonalGitHub: false, allowlist: []))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(authService.startDeviceFlowCallCount, 0)
        guard case .error = connection.authState else {
            return XCTFail("Expected blocked policy to set error authState, got \(connection.authState)")
        }
    }

    func testMCAUTH04RegisteredConnectionsRestoreIndependentlyWhenOneTokenIsExpired() async throws {
        let defaults = try makeDefaults()
        let healthyID = ConnectionID.gitHubDotCom(login: "healthy")
        let expiredID = ConnectionID.gitHubDotCom(login: "expired")
        try ConnectionRegistry(defaults: defaults).save([expiredID, healthyID])
        let store = makeStore(defaults: defaults, restoreOnInit: false) { id in
            if id == expiredID {
                return try self.makeConnection(
                    login: "expired",
                    authService: MultiConnectionAuthService(
                        login: "expired",
                        fetchUserResult: .failure(GitHubAuthError.badCredentials)
                    )
                )
            }
            return try self.makeConnection(login: "healthy")
        }

        store.restoreAllConnections()
        try await waitForStoreConnectionStates(store, count: 2)

        XCTAssertEqual(store.connections.map(\.id), [expiredID, healthyID])
        XCTAssertEqual(store.connections.first { $0.id == healthyID }?.authState, .signedIn(login: "healthy"))
        XCTAssertEqual(store.connections.first { $0.id == expiredID }?.authState, .sessionExpired(login: "expired"))
    }

    func testMCSIGNOUT02RemovingOneConnectionInvalidatesOnlyThatProviderCache() async throws {
        let defaults = try makeDefaults()
        let providerA = InvalidatingMultiConnectionProvider()
        let providerB = InvalidatingMultiConnectionProvider()
        let store = makeStore(defaults: defaults, restoreOnInit: false)
        let idA = ConnectionID.gitHubDotCom(login: "a")
        let idB = ConnectionID.gitHubDotCom(login: "b")
        try store.addConnection(
            id: idA, provider: providerA, tokenStore: MutableTokenStore(token: storedToken(login: "a"))
        )
        try store.addConnection(
            id: idB, provider: providerB, tokenStore: MutableTokenStore(token: storedToken(login: "b"))
        )

        await store.removeConnection(idA)

        let invalidateCountA = await providerA.invalidateCount()
        let invalidateCountB = await providerB.invalidateCount()
        XCTAssertEqual(invalidateCountA, 1)
        XCTAssertEqual(invalidateCountB, 0)
        XCTAssertEqual(store.connections.map(\.id), [idB])
    }

    func testMCSIGNOUT03RemovingOneConnectionStopsOnlyThatScheduler() async throws {
        let defaults = try makeDefaults()
        let sleeperA = MultiConnectionSleeper()
        let sleeperB = MultiConnectionSleeper()
        let store = makeStore(defaults: defaults, restoreOnInit: false)
        let idA = ConnectionID.gitHubDotCom(login: "a")
        let idB = ConnectionID.gitHubDotCom(login: "b")
        try store.addConnection(
            id: idA,
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: storedToken(login: "a")),
            scheduler: scheduler(sleeper: sleeperA)
        )
        try store.addConnection(
            id: idB,
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: storedToken(login: "b")),
            scheduler: scheduler(sleeper: sleeperB)
        )
        for connection in store.connections {
            connection.authState = .signedIn(login: connection.id.login)
            connection.refreshNow()
        }
        await sleeperA.awaitParked()
        await sleeperB.awaitParked()

        await store.removeConnection(idA)
        try await Task.sleep(for: .milliseconds(50))

        let cancellationCountA = await sleeperA.cancellationSnapshot()
        let cancellationCountB = await sleeperB.cancellationSnapshot()
        let isSleepingB = await sleeperB.sleepingSnapshot()
        XCTAssertGreaterThan(cancellationCountA, 0)
        XCTAssertEqual(cancellationCountB, 0)
        XCTAssertTrue(isSleepingB)
    }

    func testMCSIGNOUT04SignOutAllClearsConnectionsAggregateAndSchedulers() async throws {
        let defaults = try makeDefaults()
        let sleeperA = MultiConnectionSleeper()
        let sleeperB = MultiConnectionSleeper()
        let store = makeStore(defaults: defaults, restoreOnInit: false)
        try store.addConnection(
            id: .gitHubDotCom(login: "a"),
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: storedToken(login: "a")),
            scheduler: scheduler(sleeper: sleeperA)
        )
        try store.addConnection(
            id: .gitHubDotCom(login: "b"),
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: storedToken(login: "b")),
            scheduler: scheduler(sleeper: sleeperB)
        )
        store.connections[0].replaceData(HubberData(incoming: [incoming(id: "a")], outgoing: [], drafts: []))
        store.connections[1].replaceData(HubberData(incoming: [incoming(id: "b")], outgoing: [], drafts: []))
        for connection in store.connections {
            connection.authState = .signedIn(login: connection.id.login)
            connection.refreshNow()
        }
        await sleeperA.awaitParked()
        await sleeperB.awaitParked()

        await store.signOut()

        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertTrue(store.data.incoming.isEmpty)
        XCTAssertTrue(store.data.outgoing.isEmpty)
        XCTAssertTrue(store.data.drafts.isEmpty)
        let cancellationCountA = await sleeperA.cancellationSnapshot()
        let cancellationCountB = await sleeperB.cancellationSnapshot()
        XCTAssertGreaterThan(cancellationCountA, 0)
        XCTAssertGreaterThan(cancellationCountB, 0)
        XCTAssertTrue(ConnectionRegistry(defaults: defaults).load().isEmpty)
    }

    func testAddSecondAccountKeepsAggregateLiveAfterRebindingConnections() async throws {
        let defaults = try makeDefaults()
        let store = makeStore(
            defaults: defaults,
            primaryLogin: "first",
            restoreOnInit: false
        )
        try store.addConnection(
            id: .gitHubDotCom(login: "second"),
            tokenStore: MutableTokenStore(token: storedToken(login: "second"))
        )
        let second = try XCTUnwrap(store.connections.first { $0.id.login == "second" })

        second.replaceData(HubberData(incoming: [incoming(id: "second-pr")], outgoing: [], drafts: []))
        try await waitForAggregateIncomingIDs(store, ["second-pr"])

        XCTAssertEqual(store.data.incoming.map(\.id), ["second-pr"])
    }

    func testRegistryRoundTripRestoresSingleConnectionLikeLegacyStoreRestore() async throws {
        let defaults = try makeDefaults()
        let id = ConnectionID.gitHubDotCom(login: "roundtrip")
        try ConnectionRegistry(defaults: defaults).save([id])
        let store = makeStore(defaults: defaults, restoreOnInit: false) { _ in
            try self.makeConnection(login: "roundtrip")
        }

        store.restoreAllConnections()
        try await waitForStoreConnectionStates(store, count: 1)

        XCTAssertEqual(store.primaryConnection?.id, id)
        XCTAssertEqual(store.authState, .signedIn(login: "roundtrip"))
        XCTAssertEqual(store.signedInLogin, "roundtrip")
        XCTAssertEqual(ConnectionRegistry(defaults: defaults).load(), [id])
    }

    func testRestoreAllConnectionsRebuildsGitLabConnectionFromRegistry() throws {
        let suite = "restore-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Pre-register a GitLab connection id.
        let registry = ConnectionRegistry(defaults: defaults)
        let glID = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        try registry.append(glID)

        // Store built with restoreOnInit:false and NO injected factory → uses the default factory.
        let store = HubberStore(defaults: defaults, restoreOnInit: false)
        store.restoreAllConnections()

        let conn = try XCTUnwrap(store.connections.first { $0.id == glID })
        XCTAssertTrue(conn.provider is CachingCodeHostProvider)
        XCTAssertTrue(conn.authService is GitLabAuthService)
    }

    func testRestoreAllConnectionsPrunesRegisteredSignedOutGhostWithNoToken() async throws {
        let defaults = try makeDefaults()
        let ghostID = ConnectionID.gitHubDotCom(login: "ghost")
        try ConnectionRegistry(defaults: defaults).save([ghostID])
        let store = makeStore(defaults: defaults, restoreOnInit: false) { _ in
            try self.makeConnection(
                login: "ghost",
                tokenStore: MutableTokenStore(token: nil)
            )
        }

        store.restoreAllConnections()
        try await waitForRestoreSettled(store)

        XCTAssertTrue(store.connections.isEmpty)
        XCTAssertEqual(ConnectionRegistry(defaults: defaults).load(), [])
    }

    func testRemoveConnectionKeepsConnectionAndRegistryWhenTokenDeleteFails() async throws {
        let defaults = try makeDefaults()
        let id = ConnectionID.gitHubDotCom(login: "delete-fails")
        let store = makeStore(defaults: defaults, restoreOnInit: false)
        try store.addConnection(
            id: id,
            tokenStore: MutableTokenStore(
                token: storedToken(login: "delete-fails"),
                deleteError: MultiConnectionTokenStoreError.deleteFailed
            )
        )

        await store.removeConnection(id)

        XCTAssertEqual(store.connections.map(\.id), [id])
        XCTAssertEqual(ConnectionRegistry(defaults: defaults).load(), [id])
        guard case let .error(message) = store.connections.first?.authState else {
            return XCTFail("Expected delete failure to leave connection in error state")
        }
        XCTAssertEqual(message, "Token delete failed")
    }

    // MARK: - Codex-review hardening (#85): provider isolation, dup-id guard, popover broadcast

    func testAddConnectionWithoutExplicitProviderUsesDistinctProviderPerConnection() throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        let first = try store.addConnection(
            id: .gitHubDotCom(login: "first"),
            tokenStore: MutableTokenStore(token: storedToken(login: "first"))
        )
        let second = try store.addConnection(
            id: .gitHubDotCom(login: "second"),
            tokenStore: MutableTokenStore(token: storedToken(login: "second"))
        )
        let firstProvider = try XCTUnwrap(first.provider as? CachingCodeHostProvider)
        let secondProvider = try XCTUnwrap(second.provider as? CachingCodeHostProvider)
        XCTAssertNotEqual(
            ObjectIdentifier(firstProvider),
            ObjectIdentifier(secondProvider),
            "Connections without an explicit provider must each get their own provider/cache"
        )
    }

    func testAddConnectionWithDuplicateIDReturnsExistingConnectionWithoutAppending() throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        let id = ConnectionID.gitHubDotCom(login: "duplicate")
        let first = try store.addConnection(
            id: id,
            tokenStore: MutableTokenStore(token: storedToken(login: "duplicate"))
        )
        let second = try store.addConnection(
            id: id,
            tokenStore: MutableTokenStore(token: storedToken(login: "duplicate"))
        )
        XCTAssertTrue(first === second)
        XCTAssertEqual(store.connections.map(\.id), [id])
    }

    func testSetPopoverOpenBroadcastsToEveryConnection() throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        try store.addConnection(
            id: .gitHubDotCom(login: "first"),
            tokenStore: MutableTokenStore(token: storedToken(login: "first"))
        )
        try store.addConnection(
            id: .gitHubDotCom(login: "second"),
            tokenStore: MutableTokenStore(token: storedToken(login: "second"))
        )
        store.setPopoverOpen(true)
        XCTAssertTrue(store.isPopoverOpen)
        XCTAssertTrue(store.connections.allSatisfy(\.isPopoverOpen))
    }

    private func makeConnection(
        login: String,
        authService: MultiConnectionAuthService? = nil,
        provider: MultiConnectionProvider = MultiConnectionProvider(),
        tokenStore: (any GitHubTokenStoring)? = nil,
        sleeper: MultiConnectionSleeper? = nil
    ) throws -> Connection {
        let sleeper = sleeper ?? MultiConnectionSleeper()
        let id = ConnectionID.gitHubDotCom(login: login)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MultiConnection-\(UUID())"))
        return Connection(
            id: id,
            provider: provider,
            authService: authService ?? MultiConnectionAuthService(login: login),
            tokenStore: tokenStore ?? MutableTokenStore(token: storedToken(login: login)),
            snapshotStore: SnapshotStore(snapshotURL: temporarySnapshotURL(login: login)),
            scheduler: RefreshScheduler(
                idle: MultiConnectionIdleProvider(),
                sleep: { interval in try await sleeper.sleep(for: interval) }
            ),
            settings: SettingsStore(defaults: defaults)
        )
    }

    private func makeStore(
        defaults: UserDefaults,
        primaryLogin: String = "legacy",
        restoreOnInit: Bool,
        connectionFactory: ((ConnectionID) throws -> Connection)? = nil
    ) -> HubberStore {
        HubberStore(
            authService: MultiConnectionAuthService(login: primaryLogin),
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: storedToken(login: primaryLogin)),
            settings: SettingsStore(defaults: defaults),
            telemetry: Telemetry(sink: NullTelemetrySink()),
            snapshotStore: SnapshotStore(snapshotURL: temporarySnapshotURL(login: primaryLogin)),
            defaults: defaults,
            restoreOnInit: restoreOnInit,
            connectionFactory: connectionFactory
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "MultiConnection-\(UUID())"))
    }

    private func storedToken(login: String) -> GitHubStoredToken {
        GitHubStoredToken(
            accessToken: "token-\(login)",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: login
        )
    }

    private func temporarySnapshotURL(login: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("hubber-multi-connection-\(login)-\(UUID()).json")
    }

    private func scheduler(sleeper: MultiConnectionSleeper) -> RefreshScheduler {
        RefreshScheduler(
            idle: MultiConnectionIdleProvider(),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )
    }

    private func incoming(id: String) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: "org/repo",
            number: 1,
            title: "Needs review",
            url: nil,
            author: .marisol,
            sloClockStart: Date(),
            additions: 1,
            deletions: 1,
            files: 1
        )
    }

    private func waitForSignedIn(_ connection: Connection, login: String) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if connection.authState == .signedIn(login: login) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(login) to sign in; state: \(connection.authState)")
    }

    private func waitForStoreConnectionStates(_ store: HubberStore, count: Int) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if store.connections.count == count, !store.connections.contains(where: { $0.authState == .restoring }) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for \(count) restored connections; states: \(store.connections.map(\.authState))")
    }

    private func waitForRestoreSettled(_ store: HubberStore) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if !store.connections.contains(where: { $0.authState == .restoring }) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for restore to settle; states: \(store.connections.map(\.authState))")
    }

    private func waitForAggregateIncomingIDs(_ store: HubberStore, _ ids: [String]) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if store.data.incoming.map(\.id) == ids {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for aggregate IDs \(ids); got \(store.data.incoming.map(\.id))")
    }

    // MARK: - Regression: sign-out then sign-in (Defect 1)

    /// After signOut() empties the connection list, startSignIn() must rebuild a fresh
    /// legacy connection so the user can sign back in.  Prior to the fix, startSignIn()
    /// was a no-op because primaryConnection was nil.
    func testCanSignInAgainAfterSignOut() async throws {
        let suiteName = "SignInAfterSignOut-\(UUID())"
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        let spy = MultiConnectionAuthService(login: "legacy")
        let store2 = HubberStore(
            authService: spy,
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: nil),
            settings: SettingsStore(defaults: testDefaults),
            telemetry: Telemetry(sink: NullTelemetrySink()),
            snapshotStore: SnapshotStore(snapshotURL: temporarySnapshotURL(login: "signout-regression")),
            defaults: testDefaults,
            restoreOnInit: false
        )

        // Sign out (connections already empty since restoreOnInit: false)
        await store2.signOut()
        XCTAssertTrue(store2.connections.isEmpty, "connections should be empty after signOut")

        // startSignIn() must rebuild a connection and start device flow
        store2.startSignIn(policy: ProviderAccessPolicy(allowPersonalGitHub: true, allowlist: []))

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, spy.startDeviceFlowCallCount == 0 {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertNotNil(store2.primaryConnection, "primaryConnection must be non-nil after startSignIn post-signOut")
        XCTAssertEqual(spy.startDeviceFlowCallCount, 1, "startDeviceFlow must be called exactly once")
    }
}

private struct NullTelemetrySink: TelemetrySink {
    func send(_: String, _: [String: String]) {}
}

// swiftlint:disable file_length - growing multi-connection integration-test suite
import Foundation
import XCTest
@testable import Hubber

// MARK: - Multi-connection test doubles

private final class MultiConnectionAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let login: String
    private let fetchUserResult: Result<AuthenticatedUser, Error>?
    private var _startDeviceFlowCallCount = 0

    var startDeviceFlowCallCount: Int {
        lock.withLock { _startDeviceFlowCallCount }
    }

    init(login: String, fetchUserResult: Result<AuthenticatedUser, Error>? = nil) {
        self.login = login
        self.fetchUserResult = fetchUserResult
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        lock.withLock { _startDeviceFlowCallCount += 1 }
        guard let verificationURI = URL(string: "https://github.com/login/device") else {
            throw CodeHostAuthError.invalidResponse
        }
        return GitHubDeviceAuthorization(
            deviceCode: "device-\(login)",
            userCode: "USER-\(login)",
            verificationURI: verificationURI,
            expiresAt: Date().addingTimeInterval(600),
            interval: 1
        )
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> StoredToken {
        StoredToken(
            accessToken: "access-\(login)",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: login
        )
    }

    func refresh(_ token: StoredToken) async throws -> StoredToken {
        token
    }

    func fetchAuthenticatedUser(accessToken _: String) async throws -> AuthenticatedUser {
        if let fetchUserResult {
            return try fetchUserResult.get()
        }
        return AuthenticatedUser(login: login, name: nil, avatarUrl: nil)
    }
}

private final class MutableTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: StoredToken?
    private let deleteError: Error?

    init(token: StoredToken?, deleteError: Error? = nil) {
        self.token = token
        self.deleteError = deleteError
    }

    func load() throws -> StoredToken? {
        lock.withLock { token }
    }

    func save(_ token: StoredToken) throws {
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

/// Provider whose outgoing result can change between refreshes and which counts fetches.
private actor ScriptedProvider: CodeHostProvider {
    private var outgoingResult: Result<[OutgoingReview], Error>
    private let incomingResult: Result<[IncomingReview], Error>
    private let draftsResult: Result<[DraftReview], Error>
    private(set) var fetchCount = 0

    init(
        outgoing: Result<[OutgoingReview], Error>,
        incoming: Result<[IncomingReview], Error> = .success([]),
        drafts: Result<[DraftReview], Error> = .success([])
    ) {
        outgoingResult = outgoing
        incomingResult = incoming
        draftsResult = drafts
    }

    /// Every tab fails with `error`.
    static func allFailing(_ error: Error) -> ScriptedProvider {
        ScriptedProvider(outgoing: .failure(error), incoming: .failure(error), drafts: .failure(error))
    }

    func setOutgoing(_ result: Result<[OutgoingReview], Error>) {
        outgoingResult = result
    }

    func fetchIncomingReviews(accessToken _: String, viewerLogin _: String, mode _: IncomingReviewMode) async throws
        -> [IncomingReview] {
        try incomingResult.get()
    }

    func fetchOutgoingPullRequests(
        accessToken _: String,
        viewerLogin _: String,
        unresolvedMode _: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        fetchCount += 1
        return try outgoingResult.get()
    }

    func fetchDraftPullRequests(accessToken _: String, limit _: Int) async throws -> [DraftReview] {
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

/// Counts real incoming-review fetches so cache hits and misses are observable.
private actor CountingIncomingProvider: CodeHostProvider {
    private(set) var incomingFetchCount = 0

    func fetchIncomingReviews(
        accessToken _: String,
        viewerLogin _: String,
        mode _: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        incomingFetchCount += 1
        return []
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

/// Records the mode each fetch was made with. When `gateFirstIncoming` is set, the first incoming
/// fetch suspends until `releaseGate()` so tests can change settings mid-refresh.
private actor ModeRecordingProvider: CodeHostProvider {
    private(set) var incomingModes: [IncomingReviewMode] = []
    private(set) var unresolvedModes: [UnresolvedThreadMode] = []
    private let gateFirstIncoming: Bool
    private var gate: CheckedContinuation<Void, Never>?
    private var gateOpen = false

    init(gateFirstIncoming: Bool = false) {
        self.gateFirstIncoming = gateFirstIncoming
    }

    func releaseGate() {
        gateOpen = true
        gate?.resume()
        gate = nil
    }

    func fetchIncomingReviews(
        accessToken _: String,
        viewerLogin _: String,
        mode: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        incomingModes.append(mode)
        if gateFirstIncoming, incomingModes.count == 1, !gateOpen {
            await withCheckedContinuation { gate = $0 }
        }
        return []
    }

    func fetchOutgoingPullRequests(
        accessToken _: String,
        viewerLogin _: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        unresolvedModes.append(unresolvedMode)
        return []
    }

    func fetchDraftPullRequests(accessToken _: String, limit _: Int) async throws -> [DraftReview] {
        []
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
            provider: MultiConnectionProvider(outgoing: .failure(CodeHostAuthError.rateLimited(retryAfter: 120))),
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
            provider: MultiConnectionProvider(outgoing: .failure(CodeHostAuthError.rateLimited(retryAfter: 120)))
        )
        let connectionB = try makeConnection(login: "healthy")
        connectionA.authState = .signedIn(login: "limited")
        connectionB.authState = .signedIn(login: "healthy")

        _ = await connectionA.refreshPullRequestsFromGitHub()
        _ = await connectionB.refreshPullRequestsFromGitHub()

        XCTAssertNotNil(connectionA.rateLimitedUntil)
        XCTAssertNil(connectionB.rateLimitedUntil)
    }

    // MARK: - Outage back-off

    func testOutageDelayDoublesFromThirtySecondsAndCapsAtFifteenMinutes() {
        let delays = (1...9).map { Connection.outageDelay(failures: $0, jitter: 0) }
        XCTAssertEqual(delays, [30, 60, 120, 240, 480, 900, 900, 900, 900])
        XCTAssertEqual(Connection.outageDelay(failures: 10000, jitter: 0), 900)
    }

    func testOutageDelayJitterStaysWithinTwentyPercent() {
        XCTAssertEqual(Connection.outageDelay(failures: 3, jitter: -0.2), 96, accuracy: 0.001)
        XCTAssertEqual(Connection.outageDelay(failures: 3, jitter: 0.2), 144, accuracy: 0.001)
        // Out-of-range jitter is clamped, so the jittered delay can never exceed 1.2 x the cap.
        XCTAssertEqual(Connection.outageDelay(failures: 20, jitter: 5), 900 * 1.2, accuracy: 0.001)
        XCTAssertEqual(Connection.outageDelay(failures: 1, jitter: -5), 30 * 0.8, accuracy: 0.001)
    }

    func testTransientFailureSetsBackoffThatGrowsWithConsecutiveFailures() async throws {
        let connection = try makeConnection(
            login: "outage",
            provider: ScriptedProvider.allFailing(CodeHostAuthError.serviceUnavailable(statusCode: 503)),
            backoffJitter: { 0.2 }
        )
        connection.authState = .signedIn(login: "outage")

        var observed: [TimeInterval] = []
        for _ in 1...3 {
            connection.unavailableUntil = nil // let the next refresh run
            _ = await connection.refreshPullRequestsFromGitHub()
            try observed.append(XCTUnwrap(connection.unavailableUntil).timeIntervalSinceNow)
        }

        XCTAssertEqual(connection.consecutiveTransientFailures, 3)
        XCTAssertEqual(observed[0], 36, accuracy: 2)
        XCTAssertEqual(observed[1], 72, accuracy: 2)
        XCTAssertEqual(observed[2], 144, accuracy: 2)
        XCTAssertNil(connection.pullRequestRefreshError, "An outage is not a per-tab or global error banner")
    }

    func testScheduledRefreshSkipsWhileBackingOffThenRecoversAndResets() async throws {
        let provider = ScriptedProvider.allFailing(URLError(.notConnectedToInternet))
        let connection = try makeConnection(login: "outage", provider: provider, backoffJitter: { 0 })
        connection.authState = .signedIn(login: "outage")

        _ = await connection.refreshPullRequestsFromGitHub()
        let firstFetchCount = await provider.fetchCount
        XCTAssertEqual(firstFetchCount, 1)
        XCTAssertNotNil(connection.unavailableUntil)

        _ = await connection.refreshPullRequestsFromGitHub() // scheduled path: skipped
        let skippedFetchCount = await provider.fetchCount
        XCTAssertEqual(skippedFetchCount, 1)
        XCTAssertEqual(connection.consecutiveTransientFailures, 1)

        await provider.setOutgoing(.success([]))
        connection.unavailableUntil = Date().addingTimeInterval(-1) // back-off elapsed
        let successes = await connection.refreshPullRequestsFromGitHub()
        XCTAssertNotNil(successes)
        XCTAssertNil(connection.unavailableUntil)
        XCTAssertEqual(connection.consecutiveTransientFailures, 0)
    }

    func testSchedulerSleepsUntilBackoffEndsInsteadOfFullInterval() async throws {
        let sleeper = MultiConnectionSleeper()
        let connection = try makeConnection(
            login: "outage",
            provider: ScriptedProvider.allFailing(CodeHostAuthError.serviceUnavailable(statusCode: 502)),
            sleeper: sleeper,
            backoffJitter: { 0 }
        )
        connection.authState = .signedIn(login: "outage")

        connection.refreshNow()
        await sleeper.awaitParked()

        let intervals = await sleeper.requestedIntervals
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertEqual(interval, 30, accuracy: 2, "Wake when the back-off ends, not 5 minutes later")
    }

    func testSingleTabTransientFailureIsATabErrorNotAnOutage() async throws {
        let outage = Result<[OutgoingReview], Error>.failure(CodeHostAuthError.serviceUnavailable(statusCode: 502))
        let provider = ScriptedProvider(outgoing: outage, drafts: .failure(URLError(.timedOut)))
        let connection = try makeConnection(login: "partial", provider: provider)
        connection.authState = .signedIn(login: "partial")

        // Two of three tabs fail, but incoming succeeds: normal success path.
        let successes = await connection.refreshPullRequestsFromGitHub()

        XCTAssertNotNil(successes)
        XCTAssertNotNil(connection.outgoingError)
        XCTAssertNotNil(connection.draftsError)
        XCTAssertNil(connection.incomingError)
        XCTAssertNil(connection.unavailableUntil)
        XCTAssertEqual(connection.consecutiveTransientFailures, 0)
        XCTAssertNotNil(connection.lastPullRequestRefresh)
    }

    func testPartialSuccessResetsExistingBackoffCounter() async throws {
        let provider = ScriptedProvider(
            outgoing: .failure(CodeHostAuthError.serviceUnavailable(statusCode: 503)),
            incoming: .failure(CodeHostAuthError.serviceUnavailable(statusCode: 503)),
            drafts: .failure(CodeHostAuthError.serviceUnavailable(statusCode: 503))
        )
        let connection = try makeConnection(login: "recover", provider: provider)
        connection.authState = .signedIn(login: "recover")
        _ = await connection.refreshPullRequestsFromGitHub()
        XCTAssertEqual(connection.consecutiveTransientFailures, 1)
        XCTAssertNotNil(connection.unavailableUntil)

        // Outgoing recovers while the other tabs still 503: partial success resets the back-off.
        await provider.setOutgoing(.success([]))
        connection.unavailableUntil = nil
        let successes = await connection.refreshPullRequestsFromGitHub()
        XCTAssertNotNil(successes)
        XCTAssertEqual(connection.consecutiveTransientFailures, 0)
        XCTAssertNil(connection.unavailableUntil)
        XCTAssertNotNil(connection.incomingError)
        XCTAssertNil(connection.outgoingError)
    }

    func testAllTabsTransientFailureTriggersOutageBackoff() async throws {
        let outage = CodeHostAuthError.serviceUnavailable(statusCode: 503)
        let provider = ScriptedProvider(
            outgoing: .failure(outage),
            incoming: .failure(outage),
            drafts: .failure(URLError(.notConnectedToInternet))
        )
        let connection = try makeConnection(login: "down", provider: provider)
        connection.authState = .signedIn(login: "down")

        let successes = await connection.refreshPullRequestsFromGitHub()

        XCTAssertNil(successes)
        XCTAssertEqual(connection.consecutiveTransientFailures, 1)
        XCTAssertNotNil(connection.unavailableUntil)
        XCTAssertNil(connection.lastPullRequestRefresh)
    }

    func testMixedTransientAndNonTransientFailuresDoNotTriggerOutageBackoff() async throws {
        let provider = ScriptedProvider(
            outgoing: .failure(CodeHostAuthError.serviceUnavailable(statusCode: 503)),
            incoming: .failure(CodeHostAuthError.providerMessage("Boom")),
            drafts: .failure(CodeHostAuthError.serviceUnavailable(statusCode: 502))
        )
        let connection = try makeConnection(login: "mixed", provider: provider)
        connection.authState = .signedIn(login: "mixed")

        _ = await connection.refreshPullRequestsFromGitHub()

        XCTAssertNil(connection.unavailableUntil)
        XCTAssertEqual(connection.consecutiveTransientFailures, 0)
        XCTAssertNotNil(connection.incomingError)
        XCTAssertNotNil(connection.outgoingError)
        XCTAssertNotNil(connection.draftsError)
    }

    func testManualRefreshBypassesOutageBackoffButKeepsFailureCount() async throws {
        let sleeper = MultiConnectionSleeper()
        let provider = ScriptedProvider.allFailing(CodeHostAuthError.serviceUnavailable(statusCode: 503))
        let connection = try makeConnection(login: "outage", provider: provider, sleeper: sleeper, backoffJitter: { 0 })
        connection.authState = .signedIn(login: "outage")
        _ = await connection.refreshPullRequestsFromGitHub()
        XCTAssertEqual(connection.consecutiveTransientFailures, 1)
        XCTAssertNotNil(connection.unavailableUntil)

        connection.refreshNow()
        XCTAssertNil(connection.unavailableUntil, "Manual refresh clears the outage back-off immediately")
        XCTAssertEqual(connection.consecutiveTransientFailures, 1, "Count is kept so the delay keeps growing")

        await sleeper.awaitParked()
        let fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 2)
        XCTAssertEqual(connection.consecutiveTransientFailures, 2)
        let intervals = await sleeper.requestedIntervals
        let interval = try XCTUnwrap(intervals.first)
        XCTAssertEqual(interval, 60, accuracy: 2)
    }

    func testManualRefreshDoesNotBypassRateLimit() async throws {
        let sleeper = MultiConnectionSleeper()
        let provider = ScriptedProvider(outgoing: .success([]))
        let connection = try makeConnection(login: "limited", provider: provider, sleeper: sleeper)
        connection.authState = .signedIn(login: "limited")
        let until = Date().addingTimeInterval(600)
        connection.rateLimitedUntil = until

        connection.refreshNow()
        await sleeper.awaitParked()

        XCTAssertEqual(connection.rateLimitedUntil, until)
        let fetchCount = await provider.fetchCount
        XCTAssertEqual(fetchCount, 0)
    }

    func testCancellationIsNotCountedAsTransientFailure() async throws {
        for error in [CancellationError() as Error, URLError(.cancelled)] {
            let connection = try makeConnection(
                login: "cancel",
                provider: ScriptedProvider.allFailing(error)
            )
            connection.authState = .signedIn(login: "cancel")

            _ = await connection.refreshPullRequestsFromGitHub()

            XCTAssertEqual(connection.consecutiveTransientFailures, 0, "\(error)")
            XCTAssertNil(connection.unavailableUntil, "\(error)")
        }
    }

    func testOutageMessageShowsProviderNameAndYieldsToRateLimit() throws {
        let defaults = try makeDefaults()
        let store = makeStore(defaults: defaults, restoreOnInit: false)
        try store.addConnection(
            id: .gitHubDotCom(login: "outage"),
            tokenStore: MutableTokenStore(token: storedToken(login: "outage"))
        )
        let connection = try XCTUnwrap(store.primaryConnection)
        let now = Date()
        XCTAssertNil(store.outageMessage(now: now))

        connection.unavailableUntil = now.addingTimeInterval(300)
        XCTAssertEqual(store.outageMessage(now: now), "GitHub unavailable — retrying in 5m")
        XCTAssertEqual(store.outageMessage(now: now.addingTimeInterval(270)), "GitHub unavailable — retrying in 30s")
        XCTAssertEqual(store.outageMessage(now: now.addingTimeInterval(299)), "GitHub unavailable — retrying in 1s")
        XCTAssertNil(store.outageMessage(now: now.addingTimeInterval(300)), "Expired backoff shows no countdown")
        XCTAssertTrue(store.isCountingDown(now: now))
        XCTAssertFalse(store.isCountingDown(now: now.addingTimeInterval(301)))

        connection.rateLimitedUntil = now.addingTimeInterval(300)
        XCTAssertNil(store.outageMessage(now: now), "Rate-limit messaging takes precedence")
        XCTAssertEqual(store.rateLimitMessage(now: now), "GitHub rate limited — next refresh in 5m")
        XCTAssertEqual(
            store.rateLimitMessage(now: now.addingTimeInterval(120)),
            "GitHub rate limited — next refresh in 3m"
        )
        XCTAssertNil(store.rateLimitMessage(now: now.addingTimeInterval(300)))
        // Rate limit expired, outage still active: falls through to the outage message.
        connection.rateLimitedUntil = now.addingTimeInterval(10)
        connection.unavailableUntil = now.addingTimeInterval(100)
        XCTAssertNil(store.outageMessage(now: now))
        XCTAssertEqual(store.outageMessage(now: now.addingTimeInterval(20)), "GitHub unavailable — retrying in 2m")
    }

    // MARK: - Multi-account refresh fan-out and footer aggregation (#156)

    private func addSignedIn(
        _ store: HubberStore,
        id: ConnectionID,
        provider: any CodeHostProvider = MultiConnectionProvider(),
        sleeper: MultiConnectionSleeper = MultiConnectionSleeper()
    ) throws -> Connection {
        let connection = try store.addConnection(
            id: id,
            provider: provider,
            tokenStore: MutableTokenStore(token: storedToken(login: id.login)),
            scheduler: scheduler(sleeper: sleeper)
        )
        connection.authState = .signedIn(login: id.login)
        return connection
    }

    func testUserInitiatedRefreshFansOutToEveryConnectionWithOneTelemetryEvent() async throws {
        let spy = SpyTelemetrySink()
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false, telemetry: Telemetry(sink: spy))
        let (sleeperA, sleeperB) = (MultiConnectionSleeper(), MultiConnectionSleeper())
        let providerA = InvalidatingMultiConnectionProvider()
        let providerB = InvalidatingMultiConnectionProvider()
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "a"), provider: providerA, sleeper: sleeperA)
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "b"), provider: providerB, sleeper: sleeperB)

        store.refreshPullRequests(userInitiated: true)
        await sleeperA.awaitParked()
        await sleeperB.awaitParked()

        XCTAssertEqual(spy.calls.filter { $0.event == "refresh.manual" }.count, 1)
        let invalidatedA = await providerA.invalidateCount()
        let invalidatedB = await providerB.invalidateCount()
        XCTAssertEqual(invalidatedA, 1, "User-initiated refresh invalidates every connection's cache")
        XCTAssertEqual(invalidatedB, 1)
        XCTAssertTrue(store.connections.allSatisfy { $0.lastPullRequestRefresh != nil }, "Both connections fetched")
    }

    func testAutomaticRefreshFansOutWithoutTelemetryOrCacheInvalidation() async throws {
        let spy = SpyTelemetrySink()
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false, telemetry: Telemetry(sink: spy))
        let (sleeperA, sleeperB) = (MultiConnectionSleeper(), MultiConnectionSleeper())
        let providerA = InvalidatingMultiConnectionProvider()
        let providerB = InvalidatingMultiConnectionProvider()
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "a"), provider: providerA, sleeper: sleeperA)
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "b"), provider: providerB, sleeper: sleeperB)

        store.refreshPullRequests(userInitiated: false)
        await sleeperA.awaitParked()
        await sleeperB.awaitParked()

        XCTAssertFalse(spy.calls.contains { $0.event == "refresh.manual" })
        let invalidatedA = await providerA.invalidateCount()
        let invalidatedB = await providerB.invalidateCount()
        XCTAssertEqual(invalidatedA, 0)
        XCTAssertEqual(invalidatedB, 0)
        XCTAssertTrue(store.connections.allSatisfy { $0.lastPullRequestRefresh != nil }, "Both connections fetched")
    }

    func testRefreshSkipsSignedOutAndAlreadyRefreshingConnections() async throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        let sleeperReady = MultiConnectionSleeper()
        let providerReady = ScriptedProvider(outgoing: .success([]))
        let providerOut = ScriptedProvider(outgoing: .success([]))
        let providerBusy = ModeRecordingProvider(gateFirstIncoming: true)
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "ready"), provider: providerReady, sleeper: sleeperReady)
        let signedOut = try addSignedIn(store, id: .gitHubDotCom(login: "out"), provider: providerOut)
        signedOut.authState = .signedOut
        let busy = try addSignedIn(store, id: .gitHubDotCom(login: "busy"), provider: providerBusy)
        busy.refreshNow()
        while await providerBusy.incomingModes.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(busy.isRefreshingPullRequests)

        store.refreshPullRequests()
        await sleeperReady.awaitParked()

        let fetchesReady = await providerReady.fetchCount
        let fetchesOut = await providerOut.fetchCount
        let busyFetches = await providerBusy.incomingModes.count
        XCTAssertEqual(fetchesReady, 1)
        XCTAssertEqual(fetchesOut, 0)
        XCTAssertEqual(busyFetches, 1, "The in-flight connection is not refreshed a second time")
        await providerBusy.releaseGate()
    }

    func testRefreshAvailabilityAggregatesAcrossConnections() async throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        XCTAssertFalse(store.canRefreshPullRequests)
        XCTAssertFalse(store.canStartPullRequestRefresh)
        let signedOut = try addSignedIn(store, id: .gitHubDotCom(login: "out"))
        signedOut.authState = .signedOut
        XCTAssertFalse(store.canRefreshPullRequests, "A signed-out primary alone cannot refresh")
        let providerBusy = ModeRecordingProvider(gateFirstIncoming: true)
        let busy = try addSignedIn(store, id: .gitHubDotCom(login: "busy"), provider: providerBusy)
        XCTAssertTrue(store.canRefreshPullRequests, "A secondary can refresh even when the primary cannot")
        XCTAssertTrue(store.canStartPullRequestRefresh)

        busy.refreshNow()
        while await providerBusy.incomingModes.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.canRefreshPullRequests)
        XCTAssertTrue(store.isRefreshingPullRequests)
        XCTAssertFalse(store.canStartPullRequestRefresh, "Every eligible connection is already refreshing")
        await providerBusy.releaseGate()
    }

    func testFooterNamesSingleAffectedSecondaryWhilePrimaryIsFine() throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "primary"))
        let gitlab = try addSignedIn(store, id: ConnectionID(provider: "gitlab", host: "gitlab.com", login: "g"))
        let now = Date()

        gitlab.rateLimitedUntil = now.addingTimeInterval(300)
        XCTAssertEqual(store.rateLimitMessage(now: now), "GitLab rate limited — next refresh in 5m")
        XCTAssertTrue(store.isCountingDown(now: now))

        gitlab.rateLimitedUntil = nil
        gitlab.unavailableUntil = now.addingTimeInterval(30)
        XCTAssertEqual(store.outageMessage(now: now), "GitLab unavailable — retrying in 30s")
        XCTAssertTrue(store.isCountingDown(now: now))
    }

    func testFooterAddsLoginWhenSeveralConnectionsShareAProvider() throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "alice"))
        let bob = try addSignedIn(store, id: .gitHubDotCom(login: "bob"))
        let now = Date()

        bob.rateLimitedUntil = now.addingTimeInterval(120)
        XCTAssertEqual(store.rateLimitMessage(now: now), "GitHub (@bob) rate limited — next refresh in 2m")
    }

    func testFooterSummarisesSeveralAffectedConnectionsWithSoonestDeadline() throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        let a = try addSignedIn(store, id: .gitHubDotCom(login: "a"))
        let b = try addSignedIn(store, id: .gitHubDotCom(login: "b"))
        _ = try addSignedIn(store, id: .gitHubDotCom(login: "c"))
        let now = Date()

        a.rateLimitedUntil = now.addingTimeInterval(600)
        b.rateLimitedUntil = now.addingTimeInterval(180)
        XCTAssertEqual(store.rateLimitMessage(now: now), "2 accounts rate limited — next refresh in 3m")

        a.rateLimitedUntil = nil
        b.rateLimitedUntil = nil
        a.unavailableUntil = now.addingTimeInterval(90)
        b.unavailableUntil = now.addingTimeInterval(30)
        XCTAssertEqual(store.outageMessage(now: now), "2 accounts unavailable — retrying in 30s")
    }

    func testFooterPrecedenceAndExpiryAcrossConnections() throws {
        let store = try makeStore(defaults: makeDefaults(), restoreOnInit: false)
        let a = try addSignedIn(store, id: .gitHubDotCom(login: "a"))
        let gitlab = try addSignedIn(store, id: ConnectionID(provider: "gitlab", host: "gitlab.com", login: "g"))
        let now = Date()

        // Outage on one account, rate limit on another: rate limit wins, outage message yields.
        a.unavailableUntil = now.addingTimeInterval(60)
        gitlab.rateLimitedUntil = now.addingTimeInterval(300)
        XCTAssertEqual(store.rateLimitMessage(now: now), "GitLab rate limited — next refresh in 5m")
        XCTAssertNil(store.outageMessage(now: now))

        // The rate limit expires, the outage still shows.
        let later = now.addingTimeInterval(301)
        a.unavailableUntil = later.addingTimeInterval(45)
        XCTAssertNil(store.rateLimitMessage(now: later))
        XCTAssertEqual(store.outageMessage(now: later), "GitHub unavailable — retrying in 45s")

        // An expired deadline on another account is not counted toward the summary.
        gitlab.unavailableUntil = later.addingTimeInterval(-1)
        XCTAssertEqual(store.outageMessage(now: later), "GitHub unavailable — retrying in 45s")

        // Everything expired.
        let end = later.addingTimeInterval(60)
        XCTAssertNil(store.rateLimitMessage(now: end))
        XCTAssertNil(store.outageMessage(now: end))
        XCTAssertFalse(store.isCountingDown(now: end))
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
                        fetchUserResult: .failure(CodeHostAuthError.badCredentials)
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

    // MARK: - Cache bypass on manual refresh (#144)

    func testManualRefreshInvalidatesCacheAndRefetches() async throws {
        let spy = CountingIncomingProvider()
        let sleeper = MultiConnectionSleeper()
        let connection = try makeCachedConnection(login: "manual", spy: spy, sleeper: sleeper)
        _ = await connection.refreshPullRequestsFromGitHub() // primes the cache
        connection.refreshNow(invalidatingCache: true)
        await sleeper.awaitParked()
        let fetches = await spy.incomingFetchCount
        XCTAssertEqual(fetches, 2, "A user-initiated refresh must hit the provider despite the warm cache")
    }

    func testScheduledRefreshWithinTTLIsServedFromCache() async throws {
        let spy = CountingIncomingProvider()
        let sleeper = MultiConnectionSleeper()
        let connection = try makeCachedConnection(login: "scheduled", spy: spy, sleeper: sleeper)
        _ = await connection.refreshPullRequestsFromGitHub() // primes the cache
        connection.refreshNow()
        await sleeper.awaitParked()
        let fetches = await spy.incomingFetchCount
        XCTAssertEqual(fetches, 1, "An automatic refresh within the TTL must be served from cache")
    }

    // MARK: - Refresh on settings mode change (#142)

    func testChangingIncomingModeRefreshesEveryConnectionWithNewMode() async throws {
        let fixture = try makeModeStore(logins: ["a", "b"])
        let (store, settings, rigs) = (fixture.store, fixture.settings, fixture.rigs)
        settings.incomingMode = .team
        for rig in rigs {
            await rig.sleeper.awaitParked()
            let modes = await rig.provider.incomingModes
            XCTAssertEqual(modes, [.team])
        }
        withExtendedLifetime(store) {}
    }

    func testChangingUnresolvedModeRefreshesWithNewMode() async throws {
        let fixture = try makeModeStore(logins: ["a"])
        let (store, settings, rigs) = (fixture.store, fixture.settings, fixture.rigs)
        settings.unresolvedMode = .changesRequested
        let rig = try XCTUnwrap(rigs.first)
        await rig.sleeper.awaitParked()
        let modes = await rig.provider.unresolvedModes
        XCTAssertEqual(modes, [.changesRequested])
        withExtendedLifetime(store) {}
    }

    func testInitialModeAndUnchangedWritesDoNotFetch() async throws {
        let fixture = try makeModeStore(logins: ["a"])
        let (store, settings, rigs) = (fixture.store, fixture.settings, fixture.rigs)
        settings.incomingMode = settings.incomingMode
        settings.unresolvedMode = settings.unresolvedMode
        try await Task.sleep(for: .milliseconds(100))
        let rig = try XCTUnwrap(rigs.first)
        let incoming = await rig.provider.incomingModes
        let unresolved = await rig.provider.unresolvedModes
        XCTAssertTrue(incoming.isEmpty)
        XCTAssertTrue(unresolved.isEmpty)
        withExtendedLifetime(store) {}
    }

    func testModeChangeDuringInFlightRefreshTriggersFollowUpFetch() async throws {
        let fixture = try makeModeStore(logins: ["a"], gateFirstIncoming: true)
        let (store, settings, rigs) = (fixture.store, fixture.settings, fixture.rigs)
        let rig = try XCTUnwrap(rigs.first)
        let connection = try XCTUnwrap(store.connections.first)
        connection.refreshNow() // first fetch (old mode) suspends at the gate
        while await rig.provider.incomingModes.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(connection.isRefreshingPullRequests)

        settings.incomingMode = .team
        await rig.provider.releaseGate()
        await rig.sleeper.awaitParked()
        // Parked after the follow-up: the sleeper is only reached once the queued refresh has run.
        var modes = await rig.provider.incomingModes
        let deadline = Date().addingTimeInterval(3)
        while modes != [.explicit, .team], Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
            modes = await rig.provider.incomingModes
        }
        XCTAssertEqual(modes, [.explicit, .team])
    }

    private struct ModeFixture {
        let store: HubberStore
        let settings: SettingsStore
        let rigs: [ModeRig]
    }

    private struct ModeRig {
        let provider: ModeRecordingProvider
        let sleeper: MultiConnectionSleeper
    }

    private func makeModeStore(
        logins: [String],
        gateFirstIncoming: Bool = false
    ) throws -> ModeFixture {
        let defaults = try makeDefaults()
        let settings = SettingsStore(defaults: defaults)
        let store = HubberStore(
            authService: MultiConnectionAuthService(login: "legacy"),
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: storedToken(login: "legacy")),
            settings: settings,
            telemetry: Telemetry(sink: NullTelemetrySink()),
            snapshotStore: SnapshotStore(snapshotURL: temporarySnapshotURL(login: "legacy")),
            defaults: defaults,
            restoreOnInit: false
        )
        var rigs: [ModeRig] = []
        for login in logins {
            let rig = ModeRig(
                provider: ModeRecordingProvider(gateFirstIncoming: gateFirstIncoming),
                sleeper: MultiConnectionSleeper()
            )
            let sleeper = rig.sleeper
            let connection = try store.addConnection(
                id: .gitHubDotCom(login: login),
                provider: rig.provider,
                authService: MultiConnectionAuthService(login: login),
                tokenStore: MutableTokenStore(token: storedToken(login: login)),
                snapshotStore: SnapshotStore(snapshotURL: temporarySnapshotURL(login: login)),
                scheduler: RefreshScheduler(
                    idle: MultiConnectionIdleProvider(),
                    sleep: { interval in try await sleeper.sleep(for: interval) }
                )
            )
            connection.authState = .signedIn(login: login)
            rigs.append(rig)
        }
        return ModeFixture(store: store, settings: settings, rigs: rigs)
    }

    private func makeCachedConnection(
        login: String,
        spy: CountingIncomingProvider,
        sleeper: MultiConnectionSleeper
    ) throws -> Connection {
        let connection = try makeConnection(
            login: login,
            provider: CachingCodeHostProvider(wrapping: spy),
            sleeper: sleeper
        )
        connection.authState = .signedIn(login: login)
        return connection
    }

    private func makeConnection(
        login: String,
        authService: MultiConnectionAuthService? = nil,
        provider: any CodeHostProvider = MultiConnectionProvider(),
        tokenStore: (any TokenStoring)? = nil,
        sleeper: MultiConnectionSleeper? = nil,
        backoffJitter: @escaping @MainActor () -> Double = { 0 }
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
            settings: SettingsStore(defaults: defaults),
            backoffJitter: backoffJitter
        )
    }

    private func makeStore(
        defaults: UserDefaults,
        primaryLogin: String = "legacy",
        restoreOnInit: Bool,
        telemetry: Telemetry = Telemetry(sink: NullTelemetrySink()),
        connectionFactory: ((ConnectionID) throws -> Connection)? = nil
    ) -> HubberStore {
        HubberStore(
            authService: MultiConnectionAuthService(login: primaryLogin),
            provider: MultiConnectionProvider(),
            tokenStore: MutableTokenStore(token: storedToken(login: primaryLogin)),
            settings: SettingsStore(defaults: defaults),
            telemetry: telemetry,
            snapshotStore: SnapshotStore(snapshotURL: temporarySnapshotURL(login: primaryLogin)),
            defaults: defaults,
            restoreOnInit: restoreOnInit,
            connectionFactory: connectionFactory
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: "MultiConnection-\(UUID())"))
    }

    private func storedToken(login: String) -> StoredToken {
        StoredToken(
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

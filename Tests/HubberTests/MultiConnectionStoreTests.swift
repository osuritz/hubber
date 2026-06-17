import Foundation
import XCTest
@testable import Hubber

// MARK: - Multi-connection test doubles

private final class MultiConnectionAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    private let lock = NSLock()
    private let login: String
    private var _startDeviceFlowCallCount = 0

    var startDeviceFlowCallCount: Int {
        lock.withLock { _startDeviceFlowCallCount }
    }

    init(login: String) {
        self.login = login
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
        GitHubAuthenticatedUser(login: login, name: nil, avatarUrl: nil)
    }
}

private final class MutableTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: GitHubStoredToken?

    init(token: GitHubStoredToken?) {
        self.token = token
    }

    func load() throws -> GitHubStoredToken? {
        lock.withLock { token }
    }

    func save(_ token: GitHubStoredToken) throws {
        lock.withLock { self.token = token }
    }

    func delete() throws {
        lock.withLock { token = nil }
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

private actor MultiConnectionSleeper {
    private(set) var requestedIntervals: [TimeInterval] = []
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

    private func cancelSleep() {
        sleeping?.resume(throwing: CancellationError())
        sleeping = nil
    }
}

private struct MultiConnectionIdleProvider: MachineIdleProviding {
    let isIdle = false
}

// MARK: - Tests

@MainActor
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

    private func makeConnection(
        login: String,
        authService: MultiConnectionAuthService? = nil,
        provider: MultiConnectionProvider = MultiConnectionProvider(),
        sleeper: MultiConnectionSleeper? = nil
    ) throws -> Connection {
        let sleeper = sleeper ?? MultiConnectionSleeper()
        let id = ConnectionID.gitHubDotCom(login: login)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "MultiConnection-\(UUID())"))
        return Connection(
            id: id,
            provider: provider,
            authService: authService ?? MultiConnectionAuthService(login: login),
            tokenStore: MutableTokenStore(token: storedToken(login: login)),
            snapshotStore: SnapshotStore(snapshotURL: temporarySnapshotURL(login: login)),
            scheduler: RefreshScheduler(
                idle: MultiConnectionIdleProvider(),
                sleep: { interval in try await sleeper.sleep(for: interval) }
            ),
            settings: SettingsStore(defaults: defaults)
        )
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
}

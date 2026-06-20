import Foundation
import XCTest
@testable import Hubber

// MARK: - Test doubles (scoped to this file)

private final class MCNSpyDispatcher: NotificationDispatching, @unchecked Sendable {
    var authorizationGranted = true
    private(set) var postedContents: [NotificationContent] = []
    @MainActor var notificationsDenied: Bool {
        !authorizationGranted
    }

    func ensureAuthorized() async -> Bool {
        authorizationGranted
    }

    func post(_ content: NotificationContent) async {
        postedContents.append(content)
    }
}

private actor MCNBlockingPostGate {
    private var postedContents: [NotificationContent] = []
    private var firstPostStarted = false
    private var firstPostStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstPostRelease: CheckedContinuation<Void, Never>?

    func post(_ content: NotificationContent) async {
        postedContents.append(content)
        guard !firstPostStarted else { return }

        firstPostStarted = true
        for waiter in firstPostStartedWaiters {
            waiter.resume()
        }
        firstPostStartedWaiters.removeAll()

        await withCheckedContinuation { continuation in
            firstPostRelease = continuation
        }
    }

    func waitForFirstPostStarted() async {
        if firstPostStarted { return }

        await withCheckedContinuation { continuation in
            firstPostStartedWaiters.append(continuation)
        }
    }

    func releaseFirstPost() {
        firstPostRelease?.resume()
        firstPostRelease = nil
    }

    func contents() -> [NotificationContent] {
        postedContents
    }
}

private final class MCNBlockingFirstPostDispatcher: NotificationDispatching, @unchecked Sendable {
    private let gate = MCNBlockingPostGate()

    @MainActor var notificationsDenied: Bool {
        false
    }

    func ensureAuthorized() async -> Bool {
        true
    }

    func post(_ content: NotificationContent) async {
        await gate.post(content)
    }

    func waitForFirstPostStarted() async {
        await gate.waitForFirstPostStarted()
    }

    func releaseFirstPost() async {
        await gate.releaseFirstPost()
    }

    func postedContents() async -> [NotificationContent] {
        await gate.contents()
    }
}

private final class MCNTokenStore: TokenStoring, @unchecked Sendable {
    private var token: StoredToken?
    init(_ t: StoredToken?) {
        token = t
    }

    func load() throws -> StoredToken? {
        token
    }

    func save(_ t: StoredToken) throws {
        token = t
    }

    func delete() throws {
        token = nil
    }
}

private actor MCNAuthService: GitHubDeviceFlowServicing {
    let login: String
    init(login: String) {
        self.login = login
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        throw CodeHostAuthError.invalidResponse
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> StoredToken {
        throw CodeHostAuthError.invalidResponse
    }

    func refresh(_ token: StoredToken) async throws -> StoredToken {
        token
    }

    func fetchAuthenticatedUser(accessToken _: String) async throws -> AuthenticatedUser {
        AuthenticatedUser(login: login, name: nil, avatarUrl: nil)
    }
}

private actor MCNProvider: CodeHostProvider {
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

    func fetchDraftPullRequests(
        accessToken _: String,
        limit _: Int
    ) async throws -> [DraftReview] {
        []
    }
}

private struct MCNIdleProvider: MachineIdleProviding { let isIdle = false }
private struct MCNNullTelemetrySink: TelemetrySink { func send(_: String, _: [String: String]) {} }

// MARK: - Fixture

private struct DualConnectionFixture {
    let store: HubberStore
    let connA: Connection
    let connB: Connection
}

// MARK: - Helpers

private func tmpURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("mcnotif-\(name)-\(UUID()).json")
}

private func storedToken(login: String) -> StoredToken {
    StoredToken(
        accessToken: "tok-\(login)",
        accessTokenExpiresAt: nil,
        refreshToken: nil,
        refreshTokenExpiresAt: nil,
        tokenType: "bearer",
        login: login
    )
}

private func incomingReview(id: String, repo: String = "acme/web", number: Int = 1) -> IncomingReview {
    IncomingReview(
        id: id,
        repo: repo,
        number: number,
        title: "PR \(id)",
        url: nil,
        author: .marisol,
        sloClockStart: Date(),
        additions: 1,
        deletions: 1,
        files: 1
    )
}

private func outgoingReview(
    id: String,
    repo: String = "acme/web",
    number: Int = 1,
    reviewers: [Reviewer] = [],
    mergeable: Bool = true,
    approvals: Int = 0,
    requiredApprovals: Int = 1
) -> OutgoingReview {
    OutgoingReview(
        id: id,
        repo: repo,
        number: number,
        title: "PR \(id)",
        url: nil,
        ci: .passing,
        ciDetail: "",
        unresolved: 0,
        approvals: approvals,
        requiredApprovals: requiredApprovals,
        reviewers: reviewers,
        updatedAgoHours: 1,
        mergeable: mergeable
    )
}

// MARK: - Fixture builder

/// Builds a HubberStore (no restoreOnInit) + two Connection objects added via `addConnection`.
/// The connections are wired via `wireCallbacks` so `handleRefreshSucceeded` is called when
/// `onRefreshSucceeded` fires. Tests call `store.handleRefreshSucceeded(conn, ...)` directly
/// to avoid closure-retention lifetime issues in tests.
@MainActor
private func makeDualConnectionStore(
    loginA: String = "alice",
    loginB: String = "bob",
    spy: any NotificationDispatching,
    snapshotURLa: URL,
    snapshotURLb: URL
) throws -> DualConnectionFixture {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "MCN-\(UUID())"))
    let store = HubberStore(
        authService: MCNAuthService(login: loginA),
        provider: MCNProvider(),
        tokenStore: MCNTokenStore(storedToken(login: loginA)),
        settings: SettingsStore(defaults: defaults),
        telemetry: Telemetry(sink: MCNNullTelemetrySink()),
        dispatcher: spy,
        snapshotStore: SnapshotStore(snapshotURL: tmpURL("coordinator")),
        defaults: defaults,
        restoreOnInit: false
    )

    let connA = try store.addConnection(
        id: .gitHubDotCom(login: loginA),
        provider: MCNProvider(),
        authService: MCNAuthService(login: loginA),
        tokenStore: MCNTokenStore(storedToken(login: loginA)),
        snapshotStore: SnapshotStore(snapshotURL: snapshotURLa)
    )

    let connB = try store.addConnection(
        id: .gitHubDotCom(login: loginB),
        provider: MCNProvider(),
        authService: MCNAuthService(login: loginB),
        tokenStore: MCNTokenStore(storedToken(login: loginB)),
        snapshotStore: SnapshotStore(snapshotURL: snapshotURLb)
    )

    return DualConnectionFixture(store: store, connA: connA, connB: connB)
}

// MARK: - Tests

/// Cross-connection notification tests (Task 8 — union diff via coordinator).
/// Tests call `store.handleRefreshSucceeded(conn, tabSuccesses)` directly, which is the
/// internal coordinator method exposed via `@testable import`.
@MainActor
final class MultiConnectionNotificationTests: XCTestCase {
    func testHiddenAccountSuppressedWhenNotifyHiddenAccountsOff() {
        // Two connections' data; hide the second; with notifyHiddenAccounts == false the pass
        // should diff only the visible connection.
        let visibleID = ConnectionID.gitHubDotCom(login: "osuritz")
        let hiddenID = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let visibility = ConnectionVisibility().setting(hiddenID, visible: false)

        let all: [(id: ConnectionID, data: HubberData)] = [
            (visibleID, HubberData(incoming: [], outgoing: [], drafts: [])),
            (hiddenID, HubberData(incoming: [], outgoing: [], drafts: [])),
        ]

        XCTAssertEqual(HubberStore.notificationConnectionIDs(all, visibility: visibility, notifyHidden: true).count, 2)
        XCTAssertEqual(
            HubberStore.notificationConnectionIDs(all, visibility: visibility, notifyHidden: false),
            [visibleID]
        )
    }

    // MARK: - MC-NOTIF-02

    /// A has empty baseline, data has pr-A1.
    /// B has baseline {pr-B1}, data still has pr-B1 (unchanged).
    /// A's refresh fires exactly one newReview for pr-A1; nothing for B.
    func testMCNOTIF02ARefreshesWithNewIncomingBUnchanged() async throws {
        let spy = MCNSpyDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: spy,
            snapshotURLa: tmpURL("a"),
            snapshotURLb: tmpURL("b")
        )

        fixture.connA.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        fixture.connA.replaceData(HubberData(
            incoming: [incomingReview(id: "pr-A1")],
            outgoing: [],
            drafts: []
        ))

        fixture.connB.notificationBaseline = ReviewSnapshot(incomingIDs: ["pr-B1"], outgoing: [:])
        fixture.connB.replaceData(HubberData(
            incoming: [incomingReview(id: "pr-B1")],
            outgoing: [],
            drafts: []
        ))

        await fixture.store.handleRefreshSucceeded(fixture.connA, TabSuccesses(incoming: true, outgoing: true))

        let newReviews = spy.postedContents.filter { $0.id.hasPrefix("newReview") }
        XCTAssertEqual(newReviews.count, 1, "Exactly one newReview should fire for pr-A1")
        // Notification ID is "\(type.rawValue)-\(prID)" = "newReview-pr-A1"
        let notifID = try XCTUnwrap(newReviews.first?.id)
        XCTAssertTrue(notifID.contains("pr-A1"), "Notification ID should reference pr-A1, got \(notifID)")
    }

    // MARK: - MC-NOTIF-03

    /// Both baselines equal their current data → refresh fires nothing.
    func testMCNOTIF03BothBaselinesEqualCurrentFiresNothing() async throws {
        let spy = MCNSpyDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: spy,
            snapshotURLa: tmpURL("a"),
            snapshotURLb: tmpURL("b")
        )

        fixture.connA.notificationBaseline = ReviewSnapshot(incomingIDs: ["pr-A1"], outgoing: [:])
        fixture.connA.replaceData(HubberData(
            incoming: [incomingReview(id: "pr-A1")],
            outgoing: [],
            drafts: []
        ))

        fixture.connB.notificationBaseline = ReviewSnapshot(incomingIDs: ["pr-B1"], outgoing: [:])
        fixture.connB.replaceData(HubberData(
            incoming: [incomingReview(id: "pr-B1")],
            outgoing: [],
            drafts: []
        ))

        await fixture.store.handleRefreshSucceeded(fixture.connA, TabSuccesses(incoming: true, outgoing: true))

        XCTAssertTrue(spy.postedContents.isEmpty, "No notifications when baselines match current data")
    }

    // MARK: - MC-NOTIF-04

    /// pr-X1 outgoing under BOTH connections; alice:pending in both baselines; both now alice:approved.
    /// A's refresh fires exactly ONE reviewApproved — the mergedBaseline sees alice:pending (not approved),
    /// and the aggregate sees alice:approved → fires once, not twice.
    func testMCNOTIF04OverlappingOutgoingApprovedFiresExactlyOne() async throws {
        let spy = MCNSpyDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: spy,
            snapshotURLa: tmpURL("a"),
            snapshotURLb: tmpURL("b")
        )
        // Enable reviewApproved notifications (off by default in fresh SettingsStore)
        fixture.store.settings.notifyReviewApproved = true

        let aliceApproved = Reviewer(
            user: CodeHostUser(login: "alice", initials: "AL", color: .red),
            state: .approved
        )
        let prX1WithAliceApproved = outgoingReview(id: "pr-X1", reviewers: [aliceApproved])
        let baselineSnap = OutgoingSnapshot(
            reviewerStates: ["alice": ReviewerState.pending.rawValue],
            ci: "passing",
            mergeable: true,
            approved: false,
            repo: "acme/web",
            number: 1,
            title: "PR pr-X1",
            url: nil
        )

        // Both connections: same baseline (alice:pending), same current data (alice:approved)
        fixture.connA.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-X1": baselineSnap])
        fixture.connA.replaceData(HubberData(incoming: [], outgoing: [prX1WithAliceApproved], drafts: []))

        fixture.connB.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-X1": baselineSnap])
        fixture.connB.replaceData(HubberData(incoming: [], outgoing: [prX1WithAliceApproved], drafts: []))

        // A's refresh: mergedBaseline has alice:pending (merged from both), aggregate has alice:approved
        await fixture.store.handleRefreshSucceeded(fixture.connA, TabSuccesses(incoming: true, outgoing: true))

        let approvedEvents = spy.postedContents.filter { $0.id.hasPrefix("reviewApproved") }
        XCTAssertEqual(approvedEvents.count, 1, "Exactly ONE reviewApproved should fire for pr-X1")
    }

    // MARK: - MC-NOTIF-05

    /// removeConnection(A) deletes A's snapshot file; B's file is untouched.
    func testMCNOTIF05SignOutADeletesOnlyASnapshot() async throws {
        let urlA = tmpURL("signout-a")
        let urlB = tmpURL("signout-b")
        let spy = MCNSpyDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: spy,
            snapshotURLa: urlA,
            snapshotURLb: urlB
        )

        let snap = ReviewSnapshot(incomingIDs: ["pr-1"], outgoing: [:])
        try fixture.connA.snapshotStore.save(snap)
        try fixture.connB.snapshotStore.save(snap)

        XCTAssertTrue(FileManager.default.fileExists(atPath: urlA.path), "A snapshot should exist before sign-out")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlB.path), "B snapshot should exist before sign-out")

        await fixture.store.removeConnection(fixture.connA.id)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: urlA.path),
            "A's snapshot must be deleted after removeConnection"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: urlB.path),
            "B's snapshot must be untouched"
        )
    }

    // MARK: - MC-AGG-02 regression

    /// Same incoming id visible under both connections → aggregate deduplicates it → only ONE newReview fires.
    func testMCAGG02SameIncomingIDUnderBothConnectionsFiresOneNewReview() async throws {
        let spy = MCNSpyDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: spy,
            snapshotURLa: tmpURL("a"),
            snapshotURLb: tmpURL("b")
        )

        fixture.connA.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        fixture.connA.replaceData(HubberData(incoming: [incomingReview(id: "pr-shared")], outgoing: [], drafts: []))

        fixture.connB.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        fixture.connB.replaceData(HubberData(incoming: [incomingReview(id: "pr-shared")], outgoing: [], drafts: []))

        await fixture.store.handleRefreshSucceeded(fixture.connA, TabSuccesses(incoming: true, outgoing: true))

        let newReviews = spy.postedContents.filter { $0.id.hasPrefix("newReview") }
        XCTAssertEqual(newReviews.count, 1, "A shared incoming PR must yield exactly ONE newReview")
    }

    // MARK: - Concurrent refresh regression

    /// A's first notification post is suspended before A can advance its baseline. B is then launched
    /// while A is mid-dispatch. The store's notification serial chain makes B wait for A's full pass,
    /// including baseline advancement, so both refreshes can only produce one deduplicated newReview.
    func testConcurrentRefreshesSerializeNotificationPassesAndDoNotDoublePostSharedIncoming() async throws {
        let dispatcher = MCNBlockingFirstPostDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: dispatcher,
            snapshotURLa: tmpURL("a"),
            snapshotURLb: tmpURL("b")
        )

        fixture.connA.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        fixture.connA.replaceData(HubberData(incoming: [incomingReview(id: "pr-shared")], outgoing: [], drafts: []))

        fixture.connB.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        fixture.connB.replaceData(HubberData(incoming: [incomingReview(id: "pr-shared")], outgoing: [], drafts: []))

        let refreshA = Task {
            await fixture.store.handleRefreshSucceeded(fixture.connA, TabSuccesses(incoming: true, outgoing: true))
        }
        await dispatcher.waitForFirstPostStarted()

        let refreshB = Task {
            await fixture.store.handleRefreshSucceeded(fixture.connB, TabSuccesses(incoming: true, outgoing: true))
        }
        await Task.yield()

        await dispatcher.releaseFirstPost()
        await refreshA.value
        await refreshB.value

        let newReviews = await dispatcher.postedContents().filter { $0.id.hasPrefix("newReview") }
        XCTAssertEqual(newReviews.count, 1, "Concurrent refreshes must not double-post the shared newReview")
        let notifID = try XCTUnwrap(newReviews.first?.id)
        XCTAssertTrue(notifID.contains("pr-shared"), "Notification ID should reference pr-shared, got \(notifID)")
    }

    // MARK: - Staggered refresh

    /// A refreshes (fires event), then B refreshes with UNCHANGED data → B's refresh fires nothing.
    /// After A's baseline advances, the union baseline already includes pr-A1, so B's diff finds
    /// nothing new.
    func testStaggeredRefreshBWithUnchangedDataFiresNothing() async throws {
        let spy = MCNSpyDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: spy,
            snapshotURLa: tmpURL("a"),
            snapshotURLb: tmpURL("b")
        )

        // A: empty baseline, has pr-A1 (will fire one newReview)
        fixture.connA.notificationBaseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        fixture.connA.replaceData(HubberData(incoming: [incomingReview(id: "pr-A1")], outgoing: [], drafts: []))

        // B: baseline already has pr-B1, data still has pr-B1 (unchanged)
        fixture.connB.notificationBaseline = ReviewSnapshot(incomingIDs: ["pr-B1"], outgoing: [:])
        fixture.connB.replaceData(HubberData(incoming: [incomingReview(id: "pr-B1")], outgoing: [], drafts: []))

        // A refreshes first → fires 1 newReview for pr-A1
        await fixture.store.handleRefreshSucceeded(fixture.connA, TabSuccesses(incoming: true, outgoing: true))
        let countAfterA = spy.postedContents.count
        XCTAssertEqual(countAfterA, 1, "A's refresh should fire exactly 1 notification")

        // B refreshes with unchanged data → must fire nothing additional
        await fixture.store.handleRefreshSucceeded(fixture.connB, TabSuccesses(incoming: true, outgoing: true))
        let countAfterB = spy.postedContents.count
        let extra = countAfterB - countAfterA
        XCTAssertEqual(countAfterB, 1, "B's stale-data refresh must not fire anything; got \(extra) extra")
    }

    // MARK: - Add-account storm regression

    /// A has an established baseline matching its data.
    /// B is freshly added with nil baseline and pre-existing incoming PRs.
    /// B's first refresh must treat B's current data as known and fire nothing; after B's baseline
    /// advances, a later genuinely new incoming PR should fire exactly one notification.
    func testAddAccountNilBaselineDoesNotFireStormThenNewIncomingFiresOnce() async throws {
        let spy = MCNSpyDispatcher()
        let fixture = try makeDualConnectionStore(
            spy: spy,
            snapshotURLa: tmpURL("a"),
            snapshotURLb: tmpURL("b")
        )

        fixture.connA.notificationBaseline = ReviewSnapshot(incomingIDs: ["pr-A1"], outgoing: [:])
        fixture.connA.replaceData(HubberData(incoming: [incomingReview(id: "pr-A1")], outgoing: [], drafts: []))

        fixture.connB.notificationBaseline = nil
        fixture.connB.replaceData(HubberData(
            incoming: [
                incomingReview(id: "pr-B1", number: 1),
                incomingReview(id: "pr-B2", number: 2),
            ],
            outgoing: [],
            drafts: []
        ))

        await fixture.store.handleRefreshSucceeded(fixture.connB, TabSuccesses(incoming: true, outgoing: true))

        XCTAssertTrue(spy.postedContents.isEmpty, "Freshly added B's pre-existing PRs must not fire notifications")

        fixture.connB.replaceData(HubberData(
            incoming: [
                incomingReview(id: "pr-B1", number: 1),
                incomingReview(id: "pr-B2", number: 2),
                incomingReview(id: "pr-B3", number: 3),
            ],
            outgoing: [],
            drafts: []
        ))

        await fixture.store.handleRefreshSucceeded(fixture.connB, TabSuccesses(incoming: true, outgoing: true))

        let newReviews = spy.postedContents.filter { $0.id.hasPrefix("newReview") }
        XCTAssertEqual(newReviews.count, 1, "Only the genuinely new B PR should fire after baseline advancement")
        let notifID = try XCTUnwrap(newReviews.first?.id)
        XCTAssertTrue(notifID.contains("pr-B3"), "Notification ID should reference pr-B3, got \(notifID)")
    }
}

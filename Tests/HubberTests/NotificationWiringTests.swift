import Foundation
import XCTest
@testable import Hubber

// MARK: - Spy dispatcher (reuse pattern from NotificationDispatcherTests)

private final class WiringSpyDispatcher: NotificationDispatching, @unchecked Sendable {
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

// MARK: - Test doubles

private final class WiringTokenStore: GitHubTokenStoring, @unchecked Sendable {
    private var token: GitHubStoredToken?
    init(_ t: GitHubStoredToken?) {
        token = t
    }

    func load() throws -> GitHubStoredToken? {
        token
    }

    func save(_ t: GitHubStoredToken) throws {
        token = t
    }

    func delete() throws {
        token = nil
    }
}

private actor WiringAuthService: GitHubDeviceFlowServicing {
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        throw GitHubAuthError.invalidResponse
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        throw GitHubAuthError.invalidResponse
    }

    func refresh(_ t: GitHubStoredToken) async throws -> GitHubStoredToken {
        t
    }

    func fetchAuthenticatedUser(accessToken _: String) async throws -> GitHubAuthenticatedUser {
        GitHubAuthenticatedUser(login: "testuser", name: nil, avatarUrl: nil)
    }
}

private actor WiringProvider: CodeHostProvider {
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

private struct WiringIdleProvider: MachineIdleProviding { let isIdle = false }
private struct WiringNullTelemetrySink: TelemetrySink { func send(_: String, _: [String: String]) {} }

private func tmpURL(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wiring-\(tag)-\(UUID()).json")
}

private struct WiringFixture {
    let store: HubberStore
    let connection: Connection
}

/// Builds a HubberStore + one Connection wired with the given dispatcher and snapshot store.
@MainActor
private func makeSignedInStoreWithConnection(
    spy: WiringSpyDispatcher,
    snapshotURL: URL
) throws -> WiringFixture {
    let defaults = try XCTUnwrap(UserDefaults(suiteName: "WiringTests-\(UUID())"))
    let store = HubberStore(
        authService: WiringAuthService(),
        provider: WiringProvider(),
        tokenStore: WiringTokenStore(nil),
        settings: SettingsStore(defaults: defaults),
        telemetry: Telemetry(sink: WiringNullTelemetrySink()),
        dispatcher: spy,
        snapshotStore: SnapshotStore(snapshotURL: tmpURL("coordinator")),
        defaults: defaults,
        restoreOnInit: false
    )
    let conn = try store.addConnection(
        id: .gitHubDotCom(login: "testuser"),
        provider: WiringProvider(),
        authService: WiringAuthService(),
        tokenStore: WiringTokenStore(nil),
        snapshotStore: SnapshotStore(snapshotURL: snapshotURL)
    )
    return WiringFixture(store: store, connection: conn)
}

// MARK: - Tests

@MainActor
final class NotificationWiringTests: XCTestCase {

    // MARK: - First refresh → no notifications

    func testFirstRefreshPostsNoNotifications() async {
        let spy = WiringSpyDispatcher()
        let coordinator = NotificationCoordinator(dispatcher: spy)

        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1")],
            outgoing: [],
            drafts: []
        )
        // nil baseline → initial load → no events
        await coordinator.processRefresh(
            data: data,
            baseline: nil,
            enabledTypes: Set(NotificationEventType.allCases)
        )
        XCTAssertTrue(spy.postedContents.isEmpty, "First refresh must never fire a notification")
    }

    // MARK: - Second refresh with new incoming → exactly one notification

    func testSecondRefreshWithNewIncomingPRPostsOneNotification() async {
        let spy = WiringSpyDispatcher()
        let coordinator = NotificationCoordinator(dispatcher: spy)

        // Simulate baseline from first refresh (no incoming)
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-99", repo: "acme/web", number: 99, title: "Add feature")],
            outgoing: [],
            drafts: []
        )
        await coordinator.processRefresh(
            data: data,
            baseline: baseline,
            enabledTypes: [.newReview]
        )
        XCTAssertEqual(spy.postedContents.count, 1)
        XCTAssertTrue(spy.postedContents[0].body.contains("99"))
    }

    // MARK: - Repeated refresh with same data → no duplicate notifications

    func testRepeatedRefreshWithSameDataPostsNoNotifications() async {
        let spy = WiringSpyDispatcher()
        let coordinator = NotificationCoordinator(dispatcher: spy)

        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1")],
            outgoing: [],
            drafts: []
        )
        // First: nil baseline → no events, returns new snapshot
        let snap1 = await coordinator.processRefresh(
            data: data,
            baseline: nil,
            enabledTypes: [.newReview]
        )
        XCTAssertTrue(spy.postedContents.isEmpty)

        // Second: using snap1 as baseline with identical data → no events
        _ = await coordinator.processRefresh(
            data: data,
            baseline: snap1,
            enabledTypes: [.newReview]
        )
        XCTAssertTrue(spy.postedContents.isEmpty)
    }

    // MARK: - Tab-failure partial-merge safety (E)

    /// When the outgoing tab fails, the outgoing portion of the connection's baseline must be
    /// retained — so the coordinator's next diff does not see "disappeared" PRs and fire prMerged.
    func testOutgoingFetchFailureRetainsOutgoingBaselineAndNoPRMergedEvent() async throws {
        let spy = WiringSpyDispatcher()
        spy.authorizationGranted = true

        let fixture = try makeSignedInStoreWithConnection(spy: spy, snapshotURL: tmpURL("failure"))

        // Pre-existing baseline: one outgoing PR
        let existingOutgoingSnap = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: true,
            approved: false,
            repo: "acme/web",
            number: 42,
            title: "My PR",
            url: nil
        )
        fixture.connection.notificationBaseline = ReviewSnapshot(
            incomingIDs: [],
            outgoing: ["pr-42": existingOutgoingSnap]
        )
        // Current data: no outgoing (simulating that the outgoing fetch failed)
        fixture.connection.replaceData(HubberData(incoming: [], outgoing: [], drafts: []))

        // outgoing: false → fetch failed; baseline outgoing must be preserved → no prMerged
        await fixture.store.handleRefreshSucceeded(
            fixture.connection,
            TabSuccesses(incoming: true, outgoing: false)
        )

        let prMergedEvents = spy.postedContents.filter { $0.id.hasPrefix("prMerged") }
        XCTAssertTrue(prMergedEvents.isEmpty, "A failed outgoing fetch must not fire prMerged events")
        // The connection's baseline outgoing must be retained (not overwritten with empty)
        XCTAssertFalse(
            fixture.connection.notificationBaseline?.outgoing.isEmpty ?? true,
            "Outgoing baseline must be retained after failed fetch"
        )
    }

    func testOutgoingFetchSuccessUpdatesOutgoingBaseline() async throws {
        let spy = WiringSpyDispatcher()
        let fixture = try makeSignedInStoreWithConnection(spy: spy, snapshotURL: tmpURL("success"))

        // Start with one outgoing PR in the baseline
        let existingOutgoingSnap = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: true,
            approved: false,
            repo: "acme/web",
            number: 42,
            title: "My PR",
            url: nil
        )
        fixture.connection.notificationBaseline = ReviewSnapshot(
            incomingIDs: [],
            outgoing: ["pr-42": existingOutgoingSnap]
        )
        // Current data: pr-42 is gone (merged), pr-99 is new
        let newPR = makeOutgoing(id: "pr-99", repo: "acme/api", number: 99, title: "New thing")
        fixture.connection.replaceData(HubberData(incoming: [], outgoing: [newPR], drafts: []))

        // outgoing: true → fetch succeeded; baseline outgoing must be updated
        await fixture.store.handleRefreshSucceeded(
            fixture.connection,
            TabSuccesses(incoming: true, outgoing: true)
        )

        XCTAssertEqual(
            fixture.connection.notificationBaseline?.outgoing["pr-99"]?.repo,
            "acme/api",
            "Updated baseline must contain the new outgoing PR"
        )
        XCTAssertNil(
            fixture.connection.notificationBaseline?.outgoing["pr-42"],
            "Old PR must be gone after successful outgoing fetch"
        )
    }

    // MARK: - Helpers

    private func makeIncoming(
        id: String,
        repo: String = "acme/web",
        number: Int = 1,
        title: String = "Fix bug"
    ) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: URL(string: "https://github.com/acme/web/pull/\(number)"),
            author: GitHubUser(login: "alice", initials: "AL", color: .red),
            sloClockStart: Date(),
            additions: 5,
            deletions: 1,
            files: 1
        )
    }

    private func makeOutgoing(
        id: String,
        repo: String = "acme/web",
        number: Int = 1,
        title: String = "My PR"
    ) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: repo,
            number: number,
            title: title,
            url: URL(string: "https://github.com/\(repo)/pull/\(number)"),
            ci: .passing,
            ciDetail: "",
            unresolved: 0,
            approvals: 0,
            requiredApprovals: 1,
            reviewers: [],
            updatedAgoHours: 1,
            mergeable: true
        )
    }
}

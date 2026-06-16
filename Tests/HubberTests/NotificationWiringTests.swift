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

    func testOutgoingFetchFailureRetainsOutgoingBaselineAndNoPRMergedEvent() async {
        let spy = WiringSpyDispatcher()
        spy.authorizationGranted = true

        // Create store with spy dispatcher and a pre-existing baseline containing one outgoing PR
        let store = HubberStore(dispatcher: spy)
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
        store.notificationBaseline = ReviewSnapshot(
            incomingIDs: [],
            outgoing: ["pr-42": existingOutgoingSnap]
        )
        // Current data has no outgoing (simulating: outgoing fetch failed, so store.data.outgoing is empty)
        store.data = HubberData(incoming: [], outgoing: [], drafts: [])

        // outgoing: false → fetch failed; baseline outgoing must be preserved → no prMerged
        await store.dispatchNotifications(tabSuccesses: TabSuccesses(incoming: true, outgoing: false))

        let prMergedEvents = spy.postedContents.filter { $0.id.hasPrefix("prMerged") }
        XCTAssertTrue(prMergedEvents.isEmpty, "A failed outgoing fetch must not fire prMerged events")
        // The stored baseline outgoing must be retained (not overwritten with empty)
        XCTAssertFalse(
            store.notificationBaseline?.outgoing.isEmpty ?? true,
            "Outgoing baseline must be retained after failed fetch"
        )
    }

    func testOutgoingFetchSuccessUpdatesOutgoingBaseline() async {
        let spy = WiringSpyDispatcher()
        let store = HubberStore(dispatcher: spy)

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
        store.notificationBaseline = ReviewSnapshot(
            incomingIDs: [],
            outgoing: ["pr-42": existingOutgoingSnap]
        )
        // Current data has a different outgoing PR (pr-42 is gone, pr-99 is new)
        let newPR = makeOutgoing(id: "pr-99", repo: "acme/api", number: 99, title: "New thing")
        store.data = HubberData(incoming: [], outgoing: [newPR], drafts: [])

        // outgoing: true → fetch succeeded; baseline outgoing must be updated
        await store.dispatchNotifications(tabSuccesses: TabSuccesses(incoming: true, outgoing: true))

        XCTAssertEqual(
            store.notificationBaseline?.outgoing["pr-99"]?.repo,
            "acme/api",
            "Updated baseline must contain the new outgoing PR"
        )
        XCTAssertNil(
            store.notificationBaseline?.outgoing["pr-42"],
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

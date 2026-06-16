import Foundation
import XCTest
@testable import Hubber

// MARK: - Spy dispatcher (reuse pattern from NotificationDispatcherTests)

private final class WiringSpyDispatcher: NotificationDispatching, @unchecked Sendable {
    var authorizationGranted = true
    private(set) var postedContents: [NotificationContent] = []

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
}

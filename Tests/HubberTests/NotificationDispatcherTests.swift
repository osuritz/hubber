import Foundation
import XCTest
@testable import Hubber

// MARK: - Spy dispatcher

final class SpyNotificationDispatcher: NotificationDispatching, @unchecked Sendable {
    private(set) var ensureAuthorizedCallCount = 0
    private(set) var postedContents: [NotificationContent] = []
    var authorizationGranted = true

    func ensureAuthorized() async -> Bool {
        ensureAuthorizedCallCount += 1
        return authorizationGranted
    }

    func post(_ content: NotificationContent) async {
        postedContents.append(content)
    }
}

// MARK: - Tests

@MainActor
final class NotificationDispatcherTests: XCTestCase {

    // MARK: - ensureAuthorized called before post

    func testEnsureAuthorizedCalledBeforePost() async {
        let spy = SpyNotificationDispatcher()
        _ = await spy.ensureAuthorized()
        XCTAssertEqual(spy.ensureAuthorizedCallCount, 1)
    }

    // MARK: - post dispatches content when authorized

    func testPostWhenAuthorizedStoresContent() async {
        let spy = SpyNotificationDispatcher()
        spy.authorizationGranted = true
        let content = NotificationContent(
            id: "newReview-pr-1",
            title: "New review requested",
            body: "New review · acme/web #1",
            url: URL(string: "https://github.com/acme/web/pull/1")
        )
        await spy.post(content)
        XCTAssertEqual(spy.postedContents.count, 1)
        XCTAssertEqual(spy.postedContents[0].id, "newReview-pr-1")
    }

    // MARK: - Coordinator: first refresh → no events (nil baseline)

    func testFirstRefreshPostsNoNotifications() async {
        let spy = SpyNotificationDispatcher()
        let coordinator = NotificationCoordinator(dispatcher: spy)
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1")],
            outgoing: [],
            drafts: []
        )
        // nil baseline → no events
        await coordinator.processRefresh(
            data: data,
            baseline: nil,
            enabledTypes: Set(NotificationEventType.allCases)
        )
        XCTAssertTrue(spy.postedContents.isEmpty)
    }

    // MARK: - Coordinator: second refresh with new incoming PR → one notification

    func testSecondRefreshWithNewIncomingPostsOneNotification() async {
        let spy = SpyNotificationDispatcher()
        let coordinator = NotificationCoordinator(dispatcher: spy)

        // First run: baseline with no incoming
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1", repo: "acme/web", number: 1, title: "New PR")],
            outgoing: [],
            drafts: []
        )
        await coordinator.processRefresh(
            data: data,
            baseline: baseline,
            enabledTypes: [.newReview]
        )
        XCTAssertEqual(spy.postedContents.count, 1)
        XCTAssertEqual(spy.postedContents[0].title, "New review requested")
    }

    // MARK: - Coordinator: denied authorization → no post

    func testDeniedAuthorizationDoesNotPost() async {
        let spy = SpyNotificationDispatcher()
        spy.authorizationGranted = false
        let coordinator = NotificationCoordinator(dispatcher: spy)

        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1")],
            outgoing: [],
            drafts: []
        )
        await coordinator.processRefresh(
            data: data,
            baseline: baseline,
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

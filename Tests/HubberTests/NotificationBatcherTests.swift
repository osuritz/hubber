import Foundation
import XCTest
@testable import Hubber

@MainActor
final class NotificationBatcherTests: XCTestCase {
    private func event(
        type: NotificationEventType,
        prID: String = "pr-1",
        repo: String = "acme/web",
        number: Int = 1,
        title: String = "My PR",
        url: URL? = URL(string: "https://github.com/acme/web/pull/1")
    ) -> NotificationEvent {
        NotificationEvent(
            type: type,
            prID: prID,
            repo: repo,
            number: number,
            title: title,
            url: url
        )
    }

    // MARK: - Single event per type → specific copy

    func testSingleNewReviewProducesSpecificContent() {
        let events = [event(type: .newReview, repo: "acme/web", number: 123, title: "Fix bug")]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        XCTAssertTrue(contents[0].body.contains("acme/web"))
        XCTAssertTrue(contents[0].body.contains("123"))
    }

    func testSingleReviewApprovedProducesSpecificContent() {
        let events = [event(type: .reviewApproved, repo: "acme/api", number: 7, title: "Add endpoint")]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        XCTAssertTrue(contents[0].body.contains("acme/api"))
    }

    func testSingleChangesRequestedProducesSpecificContent() {
        let events = [event(type: .changesRequested, repo: "acme/web", number: 9)]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        XCTAssertTrue(contents[0].body.contains("9"))
    }

    func testSingleCIFailedProducesSpecificContent() {
        let events = [event(type: .ciFailed, repo: "acme/web", number: 5)]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(contents[0].title.isEmpty)
    }

    func testSinglePRMergedProducesSpecificContent() {
        let events = [event(type: .prMerged, repo: "acme/web", number: 88)]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(contents[0].title.isEmpty)
    }

    // MARK: - Multiple events of same type → batched

    func testMultipleNewReviewsBatched() {
        let events = [
            event(type: .newReview, prID: "pr-1", number: 1),
            event(type: .newReview, prID: "pr-2", number: 2),
            event(type: .newReview, prID: "pr-3", number: 3),
        ]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        XCTAssertTrue(contents[0].body.contains("3") || contents[0].title.contains("3"))
    }

    func testMultipleReviewApprovedsBatched() {
        let events = [
            event(type: .reviewApproved, prID: "pr-1"),
            event(type: .reviewApproved, prID: "pr-2"),
        ]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
    }

    // MARK: - Mixed types → one entry per type

    func testMixedTypesProduceOneEntryPerType() {
        let events = [
            event(type: .newReview, prID: "pr-1"),
            event(type: .reviewApproved, prID: "pr-2"),
            event(type: .ciFailed, prID: "pr-3"),
        ]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 3)
        let types = Set(contents.map(\.id).map { $0.prefix(while: { $0 != "-" }) })
        XCTAssertEqual(types.count, 3)
    }

    func testMixedTypesSomeBatchedSomeSingle() {
        let events = [
            event(type: .newReview, prID: "pr-1"),
            event(type: .newReview, prID: "pr-2"),
            event(type: .ciFailed, prID: "pr-3"),
        ]
        let contents = NotificationBatcher.contents(from: events)
        // newReview batched → 1, ciFailed single → 1 = total 2
        XCTAssertEqual(contents.count, 2)
    }

    // MARK: - Empty input

    func testEmptyEventsProducesNoContent() {
        let contents = NotificationBatcher.contents(from: [])
        XCTAssertTrue(contents.isEmpty)
    }

    // MARK: - URL

    func testSingleEventPreservesURL() throws {
        let url = try XCTUnwrap(URL(string: "https://github.com/acme/web/pull/42"))
        let events = [event(type: .newReview, prID: "pr-42", url: url)]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents[0].url, url)
    }

    func testBatchedEventsURLIsNil() throws {
        let url1 = try XCTUnwrap(URL(string: "https://github.com/acme/web/pull/1"))
        let events = try [
            event(type: .newReview, prID: "pr-1", url: url1),
            event(type: .newReview, prID: "pr-2", url: XCTUnwrap(URL(string: "https://github.com/acme/web/pull/2"))),
        ]
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        // batched notifications have no single-PR url to open
        XCTAssertNil(contents[0].url)
    }
}

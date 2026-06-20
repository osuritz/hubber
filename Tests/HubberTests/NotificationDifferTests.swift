import Foundation
import XCTest
@testable import Hubber

// MARK: - Fixtures

private extension CodeHostUser {
    static let alice = CodeHostUser(login: "alice", initials: "AL", color: .red)
    static let bob = CodeHostUser(login: "bob", initials: "BO", color: .blue)
}

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
        author: .alice,
        sloClockStart: Date(),
        additions: 10,
        deletions: 2,
        files: 1
    )
}

private func makeOutgoing(
    id: String,
    repo: String = "acme/web",
    number: Int = 42,
    title: String = "My PR",
    ci: PullRequestCI = .passing,
    reviewers: [Reviewer] = [],
    approvals: Int = 0,
    requiredApprovals: Int = 1,
    mergeable: Bool = true
) -> OutgoingReview {
    OutgoingReview(
        id: id,
        repo: repo,
        number: number,
        title: title,
        url: URL(string: "https://github.com/acme/web/pull/\(number)"),
        ci: ci,
        ciDetail: "",
        unresolved: 0,
        approvals: approvals,
        requiredApprovals: requiredApprovals,
        reviewers: reviewers,
        updatedAgoHours: 1,
        mergeable: mergeable
    )
}

private func reviewer(_ user: CodeHostUser, state: ReviewerState) -> Reviewer {
    Reviewer(user: user, state: state)
}

// MARK: - Tests

@MainActor
final class NotificationDifferTests: XCTestCase {

    // MARK: - nil baseline → no events (initial load, #34)

    func testNilBaselineProducesNoEvents() {
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1")],
            outgoing: [makeOutgoing(id: "pr-2")],
            drafts: []
        )
        let events = NotificationDiffer.events(
            previous: nil,
            current: data,
            enabled: Set(NotificationEventType.allCases)
        )
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - snapshot(from:)

    func testSnapshotFromDataCapturesIncomingIDs() {
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1"), makeIncoming(id: "pr-2")],
            outgoing: [],
            drafts: []
        )
        let snapshot = NotificationDiffer.snapshot(from: data)
        XCTAssertEqual(snapshot.incomingIDs, ["pr-1", "pr-2"])
    }

    func testSnapshotFromDataCapturesOutgoingCI() {
        let outgoing = makeOutgoing(id: "pr-42", ci: .failing)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let snapshot = NotificationDiffer.snapshot(from: data)
        XCTAssertEqual(snapshot.outgoing["pr-42"]?.ci, PullRequestCI.failing.rawValue)
    }

    func testSnapshotFromDataCapturesMergeable() {
        let outgoing = makeOutgoing(id: "pr-42", mergeable: false)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let snapshot = NotificationDiffer.snapshot(from: data)
        XCTAssertEqual(snapshot.outgoing["pr-42"]?.mergeable, false)
    }

    func testSnapshotApprovedWhenApprovalsGEQRequired() {
        let outgoing = makeOutgoing(id: "pr-42", approvals: 2, requiredApprovals: 2)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let snapshot = NotificationDiffer.snapshot(from: data)
        XCTAssertTrue(snapshot.outgoing["pr-42"]?.approved ?? false)
    }

    func testSnapshotNotApprovedWhenApprovalsLessThanRequired() {
        let outgoing = makeOutgoing(id: "pr-42", approvals: 0, requiredApprovals: 1)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let snapshot = NotificationDiffer.snapshot(from: data)
        XCTAssertFalse(snapshot.outgoing["pr-42"]?.approved ?? true)
    }

    func testSnapshotCapturesReviewerStates() {
        let outgoing = makeOutgoing(
            id: "pr-42",
            reviewers: [reviewer(.alice, state: .approved), reviewer(.bob, state: .pending)]
        )
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let snapshot = NotificationDiffer.snapshot(from: data)
        XCTAssertEqual(snapshot.outgoing["pr-42"]?.reviewerStates["alice"], "approved")
        XCTAssertEqual(snapshot.outgoing["pr-42"]?.reviewerStates["bob"], "pending")
    }

    // MARK: - newReview (#38)

    func testNewIncomingFiresNewReviewEvent() {
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1", repo: "acme/web", number: 1, title: "New PR")],
            outgoing: [],
            drafts: []
        )
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.newReview])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .newReview)
        XCTAssertEqual(events[0].prID, "pr-1")
        XCTAssertEqual(events[0].repo, "acme/web")
        XCTAssertEqual(events[0].number, 1)
        XCTAssertEqual(events[0].title, "New PR")
    }

    func testExistingIncomingDoesNotFireNewReview() {
        let baseline = ReviewSnapshot(incomingIDs: ["pr-1"], outgoing: [:])
        let data = HubberData(incoming: [makeIncoming(id: "pr-1")], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.newReview])
        XCTAssertTrue(events.isEmpty)
    }

    func testNewReviewDisabledExcludesEvent() {
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        let data = HubberData(incoming: [makeIncoming(id: "pr-1")], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [])
        XCTAssertTrue(events.isEmpty)
    }

    func testMultipleNewIncomingFiresMultipleEvents() {
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: [:])
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1"), makeIncoming(id: "pr-2")],
            outgoing: [],
            drafts: []
        )
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.newReview])
        XCTAssertEqual(events.count(where: { $0.type == .newReview }), 2)
    }

    // MARK: - reviewApproved (#39)

    func testReviewerApprovedFiresEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["alice": "pending"],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", reviewers: [reviewer(.alice, state: .approved)])
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.reviewApproved])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .reviewApproved)
        XCTAssertEqual(events[0].prID, "pr-42")
    }

    func testAlreadyApprovedReviewerDoesNotRefire() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["alice": "approved"],
            ci: "passing",
            mergeable: true,
            approved: true
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", reviewers: [reviewer(.alice, state: .approved)])
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.reviewApproved])
        XCTAssertTrue(events.isEmpty)
    }

    func testReviewApprovedDisabledExcludesEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["alice": "pending"],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", reviewers: [reviewer(.alice, state: .approved)])
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [])
        XCTAssertTrue(events.isEmpty)
    }

    func testOnlyOneReviewApprovedEventPerPR() {
        // Two reviewers both newly approved → still one event per PR
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["alice": "pending", "bob": "pending"],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", reviewers: [
            reviewer(.alice, state: .approved),
            reviewer(.bob, state: .approved),
        ])
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.reviewApproved])
        XCTAssertEqual(events.count(where: { $0.type == .reviewApproved }), 1)
    }

    // MARK: - changesRequested (#40)

    func testChangesRequestedFiresEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["bob": "pending"],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", reviewers: [reviewer(.bob, state: .changesRequested)])
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.changesRequested])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .changesRequested)
    }

    func testAlreadyChangesRequestedDoesNotRefire() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["bob": "changesRequested"],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", reviewers: [reviewer(.bob, state: .changesRequested)])
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.changesRequested])
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - ciFailed (#41)

    func testCIPassingToFailingFiresEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", ci: .failing)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.ciFailed])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .ciFailed)
    }

    func testCIAlreadyFailingDoesNotRefire() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "failing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", ci: .failing)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.ciFailed])
        XCTAssertTrue(events.isEmpty)
    }

    func testCIRunningToFailingFiresEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "running",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", ci: .failing)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.ciFailed])
        XCTAssertEqual(events.count(where: { $0.type == .ciFailed }), 1)
    }

    // MARK: - prMerged (#42)

    func testOutgoingRemovedWhenMergeableFiresPRMerged() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let data = HubberData(incoming: [], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.prMerged])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].type, .prMerged)
    }

    func testOutgoingRemovedWhenApprovedFiresPRMerged() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: false,
            approved: true
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let data = HubberData(incoming: [], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.prMerged])
        XCTAssertEqual(events.count(where: { $0.type == .prMerged }), 1)
    }

    func testOutgoingRemovedWhenNeitherMergeableNorApprovedDoesNotFirePRMerged() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: false,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let data = HubberData(incoming: [], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [.prMerged])
        XCTAssertTrue(events.isEmpty)
    }

    // MARK: - prMerged carries real metadata from snapshot (A)

    func testPRMergedEventCarriesRepoNumberTitleAndURL() throws {
        // Build snapshot via snapshot(from:) so metadata is persisted from the OutgoingReview
        let pr = makeOutgoing(id: "pr-42", repo: "acme/web", number: 42, title: "Ship feature")
        let data = HubberData(incoming: [], outgoing: [pr], drafts: [])
        let baseline = NotificationDiffer.snapshot(from: data)
        // Now the PR disappears (merged)
        let emptyData = HubberData(incoming: [], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: emptyData, enabled: [.prMerged])
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.type, .prMerged)
        XCTAssertFalse(event.repo.isEmpty, "repo must be non-empty")
        XCTAssertEqual(event.repo, "acme/web")
        XCTAssertEqual(event.number, 42)
        XCTAssertEqual(event.title, "Ship feature")
        XCTAssertNotNil(event.url, "url must be set from snapshot")
    }

    func testPRMergedBatchedBodyIsNonBlank() {
        let pr = makeOutgoing(id: "pr-42", repo: "acme/web", number: 42, title: "Ship feature")
        let data = HubberData(incoming: [], outgoing: [pr], drafts: [])
        let baseline = NotificationDiffer.snapshot(from: data)
        let emptyData = HubberData(incoming: [], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: emptyData, enabled: [.prMerged])
        let contents = NotificationBatcher.contents(from: events)
        XCTAssertEqual(contents.count, 1)
        XCTAssertFalse(contents[0].body.isEmpty, "batched body must not be blank")
        XCTAssertTrue(contents[0].body.contains("acme/web"), "body must contain repo")
        XCTAssertTrue(contents[0].body.contains("42"), "body must contain PR number")
    }

    // MARK: - disabled → excluded (F: changesRequested, ciFailed, prMerged)

    func testChangesRequestedDisabledExcludesEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["bob": "pending"],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", reviewers: [reviewer(.bob, state: .changesRequested)])
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [])
        XCTAssertFalse(events.contains { $0.type == .changesRequested })
    }

    func testCIFailedDisabledExcludesEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(id: "pr-42", ci: .failing)
        let data = HubberData(incoming: [], outgoing: [outgoing], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [])
        XCTAssertFalse(events.contains { $0.type == .ciFailed })
    }

    func testPRMergedDisabledExcludesEvent() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: [:],
            ci: "passing",
            mergeable: true,
            approved: false
        )
        let baseline = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-42": prevOutgoing])
        let data = HubberData(incoming: [], outgoing: [], drafts: [])
        let events = NotificationDiffer.events(previous: baseline, current: data, enabled: [])
        XCTAssertFalse(events.contains { $0.type == .prMerged })
    }

    // MARK: - unchanged → no events

    func testUnchangedDataProducesNoEvents() {
        let prevOutgoing = OutgoingSnapshot(
            reviewerStates: ["alice": "approved"],
            ci: "passing",
            mergeable: true,
            approved: true
        )
        let baseline = ReviewSnapshot(incomingIDs: ["pr-1"], outgoing: ["pr-42": prevOutgoing])
        let outgoing = makeOutgoing(
            id: "pr-42",
            ci: .passing,
            reviewers: [reviewer(.alice, state: .approved)],
            approvals: 1,
            requiredApprovals: 1,
            mergeable: true
        )
        let data = HubberData(
            incoming: [makeIncoming(id: "pr-1")],
            outgoing: [outgoing],
            drafts: []
        )
        let events = NotificationDiffer.events(
            previous: baseline,
            current: data,
            enabled: Set(NotificationEventType.allCases)
        )
        XCTAssertTrue(events.isEmpty)
    }
}

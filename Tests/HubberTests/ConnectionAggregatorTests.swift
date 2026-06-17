import XCTest
@testable import Hubber

@MainActor
final class ConnectionAggregatorTests: XCTestCase {
    private let baseDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testMCAGG01DistinctIncomingAcrossConnectionsAggregateToFiveItems() {
        let first = data(incoming: [
            incoming(id: "pr-a1", sloClockStart: baseDate.addingTimeInterval(10)),
            incoming(id: "pr-a2", sloClockStart: baseDate.addingTimeInterval(20)),
        ])
        let second = data(incoming: [
            incoming(id: "pr-b1", sloClockStart: baseDate.addingTimeInterval(30)),
            incoming(id: "pr-b2", sloClockStart: baseDate.addingTimeInterval(40)),
            incoming(id: "pr-b3", sloClockStart: baseDate.addingTimeInterval(50)),
        ])

        let aggregate = ConnectionAggregator.aggregate([first, second])

        XCTAssertEqual(aggregate.incoming.count, 5)
        XCTAssertEqual(Set(aggregate.incoming.map(\.id)), ["pr-a1", "pr-a2", "pr-b1", "pr-b2", "pr-b3"])
    }

    func testMCAGG02DuplicateIncomingKeepsEarliestSLOClockStart() {
        let later = baseDate.addingTimeInterval(3600)
        let earlier = baseDate.addingTimeInterval(60)
        let first = data(incoming: [incoming(id: "pr-x1", sloClockStart: later, title: "Later")])
        let second = data(incoming: [incoming(id: "pr-x1", sloClockStart: earlier, title: "Earlier")])

        let aggregate = ConnectionAggregator.aggregate([first, second])

        XCTAssertEqual(aggregate.incoming.count, 1)
        XCTAssertEqual(aggregate.incoming[0].id, "pr-x1")
        XCTAssertEqual(aggregate.incoming[0].sloClockStart, earlier)
        XCTAssertEqual(aggregate.incoming[0].title, "Earlier")
    }

    func testMCAGG03OutgoingSortsByUpdatedAgoHoursAscending() {
        let first = data(outgoing: [
            outgoing(id: "pr-3h", updatedAgoHours: 3),
            outgoing(id: "pr-1h", updatedAgoHours: 1),
        ])
        let second = data(outgoing: [outgoing(id: "pr-2h", updatedAgoHours: 2)])

        let aggregate = ConnectionAggregator.aggregate([first, second])

        XCTAssertEqual(aggregate.outgoing.map(\.id), ["pr-1h", "pr-2h", "pr-3h"])
    }

    func testMCAGG04DuplicateDraftIDAcrossConnectionsKeepsOneDraft() {
        let firstDraft = draft(id: "draft-1", title: "First")
        let duplicateDraft = draft(id: "draft-1", title: "Duplicate")
        let first = data(drafts: [firstDraft])
        let second = data(drafts: [duplicateDraft])

        let aggregate = ConnectionAggregator.aggregate([first, second])

        XCTAssertEqual(aggregate.drafts.count, 1)
        XCTAssertEqual(aggregate.drafts[0].id, "draft-1")
        XCTAssertEqual(aggregate.drafts[0].title, "First")
    }

    func testMCAGG05EmptyConnectionDoesNotDropOtherData() {
        let nonEmpty = data(
            incoming: [incoming(id: "pr-incoming")],
            outgoing: [outgoing(id: "pr-outgoing")],
            drafts: [draft(id: "draft-1")]
        )

        let aggregate = ConnectionAggregator.aggregate([nonEmpty, emptyData()])

        XCTAssertEqual(aggregate.incoming.map(\.id), ["pr-incoming"])
        XCTAssertEqual(aggregate.outgoing.map(\.id), ["pr-outgoing"])
        XCTAssertEqual(aggregate.drafts.map(\.id), ["draft-1"])
    }

    func testMCBADGE02DuplicateIncomingContributesOneAttentionItemAfterAggregation() {
        let first = data(incoming: [incoming(id: "pr-shared")])
        let second = data(incoming: [incoming(id: "pr-shared", sloClockStart: baseDate.addingTimeInterval(-60))])

        let aggregate = ConnectionAggregator.aggregate([first, second])

        XCTAssertEqual(aggregate.incoming.count, 1)
        XCTAssertEqual(AttentionState.attentionCount(data: aggregate), 1)
    }

    func testMCBADGE04NonEmptyAggregateIsNotAllGreenWhenOneConnectionIsEmpty() {
        let oneIncoming = data(incoming: [incoming(id: "pr-needs-review")])

        let aggregate = ConnectionAggregator.aggregate([emptyData(), oneIncoming])

        XCTAssertFalse(AttentionState.isAllGreen(data: aggregate))
    }

    func testMergedBaselineUnionsIncomingIDsAndKeepsFirstOutgoingMetadata() throws {
        let firstOutgoing = snapshot(ci: .passing, title: "First")
        let duplicateOutgoing = snapshot(ci: .failing, title: "Second")
        let first = ReviewSnapshot(
            incomingIDs: ["pr-a", "pr-shared"],
            outgoing: ["pr-shared-outgoing": firstOutgoing]
        )
        let second = ReviewSnapshot(
            incomingIDs: ["pr-b", "pr-shared"],
            outgoing: [
                "pr-shared-outgoing": duplicateOutgoing,
                "pr-b-outgoing": snapshot(ci: .running, title: "B"),
            ]
        )

        let merged = ConnectionAggregator.mergedBaseline([first, second])

        XCTAssertEqual(merged.incomingIDs, ["pr-a", "pr-b", "pr-shared"])
        let sharedOutgoing = try XCTUnwrap(merged.outgoing["pr-shared-outgoing"])
        XCTAssertEqual(sharedOutgoing.title, "First")
        XCTAssertEqual(sharedOutgoing.ci, PullRequestCI.failing.rawValue)
        XCTAssertEqual(merged.outgoing["pr-b-outgoing"]?.title, "B")
    }

    // MARK: - mergedBaseline overlapping-outgoing: OR booleans + UNION reviewerStates (R4)

    /// Two baselines with the same outgoing id: one has approved:false/alice:pending,
    /// the other approved:true/alice:approved → merged has approved==true, alice=="approved".
    func testMergedBaselineOverlappingOutgoingMergesBoolsAndReviewerStates() throws {
        let snapA = OutgoingSnapshot(
            reviewerStates: ["alice": ReviewerState.pending.rawValue],
            ci: "passing",
            mergeable: false,
            approved: false,
            repo: "acme/web",
            number: 7,
            title: "My PR",
            url: nil
        )
        let snapB = OutgoingSnapshot(
            reviewerStates: ["alice": ReviewerState.approved.rawValue],
            ci: "failing",
            mergeable: true,
            approved: true,
            repo: "acme/web", // same repo/number/title (static metadata from first)
            number: 7,
            title: "My PR",
            url: nil
        )
        let first = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-7": snapA])
        let second = ReviewSnapshot(incomingIDs: [], outgoing: ["pr-7": snapB])

        let merged = ConnectionAggregator.mergedBaseline([first, second])

        let mergedSnap = try XCTUnwrap(merged.outgoing["pr-7"])
        XCTAssertTrue(mergedSnap.approved, "approved should be OR'd: false | true = true")
        XCTAssertTrue(mergedSnap.mergeable, "mergeable should be OR'd: false | true = true")
        XCTAssertEqual(
            mergedSnap.reviewerStates["alice"],
            ReviewerState.approved.rawValue,
            "alice's state should be 'approved' (wins over 'pending')"
        )
        // Static metadata kept from first
        XCTAssertEqual(mergedSnap.repo, "acme/web")
        XCTAssertEqual(mergedSnap.number, 7)
        XCTAssertEqual(mergedSnap.title, "My PR")
    }

    func testMergedBaselineOverlappingOutgoingCIFailingWinsRegardlessOfOrder() throws {
        let passing = ReviewSnapshot(
            incomingIDs: [],
            outgoing: ["pr-7": snapshot(ci: .passing, title: "My PR")]
        )
        let failing = ReviewSnapshot(
            incomingIDs: [],
            outgoing: ["pr-7": snapshot(ci: .failing, title: "My PR")]
        )

        let passingThenFailing = ConnectionAggregator.mergedBaseline([passing, failing])
        let failingThenPassing = ConnectionAggregator.mergedBaseline([failing, passing])

        XCTAssertEqual(
            try XCTUnwrap(passingThenFailing.outgoing["pr-7"]).ci,
            PullRequestCI.failing.rawValue
        )
        XCTAssertEqual(
            try XCTUnwrap(failingThenPassing.outgoing["pr-7"]).ci,
            PullRequestCI.failing.rawValue
        )
    }

    private func data(
        incoming: [IncomingReview] = [],
        outgoing: [OutgoingReview] = [],
        drafts: [DraftReview] = []
    ) -> HubberData {
        HubberData(incoming: incoming, outgoing: outgoing, drafts: drafts)
    }

    private func emptyData() -> HubberData {
        HubberData(incoming: [], outgoing: [], drafts: [])
    }

    private func incoming(
        id: String,
        sloClockStart: Date? = nil,
        title: String = "Needs review"
    ) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: "acme/app",
            number: 1,
            title: title,
            url: nil,
            author: .marisol,
            sloClockStart: sloClockStart ?? baseDate,
            additions: 10,
            deletions: 2,
            files: 1
        )
    }

    private func outgoing(id: String, updatedAgoHours: Double = 1) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: "acme/api",
            number: 2,
            title: "Outgoing",
            url: nil,
            ci: .passing,
            ciDetail: "passing",
            unresolved: 0,
            approvals: 1,
            requiredApprovals: 1,
            reviewers: [],
            updatedAgoHours: updatedAgoHours,
            mergeable: true
        )
    }

    private func draft(id: String, title: String = "Draft", updatedAt: Date? = nil) -> DraftReview {
        DraftReview(
            id: id,
            repo: "acme/api",
            number: 3,
            title: title,
            url: nil,
            ci: .pending,
            ciDetail: "pending",
            commits: 1,
            updatedAt: updatedAt ?? baseDate
        )
    }

    private func snapshot(ci: PullRequestCI, title: String) -> OutgoingSnapshot {
        OutgoingSnapshot(
            reviewerStates: [:],
            ci: ci.rawValue,
            mergeable: true,
            approved: false,
            title: title
        )
    }
}

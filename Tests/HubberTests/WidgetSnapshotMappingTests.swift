import Foundation
import HubberKit
import XCTest
@testable import Hubber

@MainActor
final class WidgetSnapshotMappingTests: XCTestCase {

    // MARK: - Fixtures

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let connectionID = ConnectionID.gitHubDotCom(login: "alice")

    private func makeConnections() -> [(id: ConnectionID, displayName: String)] {
        [(id: connectionID, displayName: "GitHub")]
    }

    private func makeIncoming(
        id: String = "pr-in-1",
        sloClockStart: Date? = nil
    ) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: "acme/app",
            number: 10,
            title: "Review me",
            url: URL(string: "https://github.com/acme/app/pull/10"),
            author: CodeHostUser(login: "bob", initials: "BO", color: .gray),
            sloClockStart: sloClockStart ?? fixedDate,
            additions: 5,
            deletions: 2,
            files: 1
        )
    }

    private func makeOutgoing(
        id: String = "pr-out-1",
        ci: PullRequestCI = .passing,
        unresolved: Int = 0,
        reviewers: [Reviewer] = [],
        approvals: Int = 1,
        requiredApprovals: Int = 1
    ) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: "acme/api",
            number: 20,
            title: "My PR",
            url: URL(string: "https://github.com/acme/api/pull/20"),
            ci: ci,
            ciDetail: ci.rawValue,
            unresolved: unresolved,
            approvals: approvals,
            requiredApprovals: requiredApprovals,
            reviewers: reviewers,
            updatedAgoHours: 3.0,
            mergeable: true,
            additions: 40,
            deletions: 10,
            files: 4
        )
    }

    private func makeDraft(
        id: String = "pr-draft-1",
        ci: PullRequestCI = .pending
    ) -> DraftReview {
        DraftReview(
            id: id,
            repo: "acme/new",
            number: 30,
            title: "WIP draft",
            url: URL(string: "https://github.com/acme/new/pull/30"),
            ci: ci,
            ciDetail: ci.rawValue,
            commits: 3,
            updatedAt: fixedDate,
            additions: 100,
            deletions: 20,
            files: 8
        )
    }

    // MARK: - Basic field mapping for incoming

    func testIncomingFieldsAreMappedCorrectly() throws {
        let review = makeIncoming()
        let snapshot = WidgetSnapshot.from(
            incoming: [review],
            outgoing: [],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        let row = try XCTUnwrap(snapshot.incoming.first)
        XCTAssertEqual(row.id, "pr-in-1")
        XCTAssertEqual(row.repo, "acme/app")
        XCTAssertEqual(row.number, 10)
        XCTAssertEqual(row.title, "Review me")
        XCTAssertEqual(row.url, URL(string: "https://github.com/acme/app/pull/10"))
        XCTAssertEqual(row.additions, 5)
        XCTAssertEqual(row.deletions, 2)
        XCTAssertEqual(row.files, 1)
        XCTAssertEqual(row.ci, .noChecks)
        XCTAssertEqual(row.review, .none)
    }

    // MARK: - needsAttention: Incoming

    func testIncomingAlwaysNeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [makeIncoming()],
            outgoing: [],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.incoming[0].needsAttention)
    }

    // MARK: - needsAttention: Outgoing

    func testOutgoingWithFailingCINeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .failing)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.outgoing[0].needsAttention)
    }

    func testOutgoingWithPassingCIAndNoUnresolvedDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .passing, unresolved: 0)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.outgoing[0].needsAttention)
    }

    func testOutgoingWithUnresolvedThreadsNeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .passing, unresolved: 2)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.outgoing[0].needsAttention)
    }

    func testOutgoingWithRunningCIAndNoUnresolvedDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [makeOutgoing(ci: .running, unresolved: 0)],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.outgoing[0].needsAttention)
    }

    // MARK: - needsAttention: Draft

    func testDraftWithFailingCINeedsAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [makeDraft(ci: .failing)],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.drafts[0].needsAttention)
    }

    func testDraftWithPassingCIDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [makeDraft(ci: .passing)],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.drafts[0].needsAttention)
    }

    func testDraftWithPendingCIDoesNotNeedAttention() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [makeDraft(ci: .pending)],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.drafts[0].needsAttention)
    }

    // MARK: - CIState mapping

    func testCIStateMappingAllCases() {
        let cases: [(PullRequestCI, CIState)] = [
            (.passing, .passing),
            (.failing, .failing),
            (.running, .running),
            (.pending, .pending),
            (.noChecks, .noChecks),
        ]
        for (liveCi, expectedDto) in cases {
            let snapshot = WidgetSnapshot.from(
                incoming: [],
                outgoing: [makeOutgoing(ci: liveCi)],
                drafts: [],
                connections: makeConnections(),
                isSignedIn: true,
                lastUpdated: fixedDate
            )
            XCTAssertEqual(snapshot.outgoing[0].ci, expectedDto, "Expected \(liveCi) → \(expectedDto)")
        }
    }

    // MARK: - ReviewSummary mapping from ReviewVerdict

    func testReviewSummaryApproved() {
        let outgoing = makeOutgoing(reviewers: [], approvals: 1, requiredApprovals: 1)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, ReviewSummary.approved)
    }

    func testReviewSummaryChangesRequested() {
        let reviewer = Reviewer(
            user: CodeHostUser(login: "carol", initials: "CA", color: .blue),
            state: .changesRequested
        )
        let outgoing = makeOutgoing(reviewers: [reviewer], approvals: 0, requiredApprovals: 1)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, ReviewSummary.changesRequested)
    }

    func testReviewSummaryPendingWhenNoReviewers() {
        // No reviewers, 0 approvals → awaitingReview → .pending
        let outgoing = makeOutgoing(reviewers: [], approvals: 0, requiredApprovals: 1)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, ReviewSummary.pending)
    }

    func testReviewSummaryCommentedWhenInReview() {
        let reviewer = Reviewer(
            user: CodeHostUser(login: "dave", initials: "DA", color: .green),
            state: .commented
        )
        let outgoing = makeOutgoing(reviewers: [reviewer], approvals: 0, requiredApprovals: 1)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.outgoing[0].review, ReviewSummary.commented)
    }

    // MARK: - Meta and connection list

    func testMetaIsSignedInPreserved() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [],
            connections: [],
            isSignedIn: false,
            lastUpdated: fixedDate
        )
        XCTAssertFalse(snapshot.meta.isSignedIn)
    }

    func testConnectionListMapped() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [],
            connections: [(id: connectionID, displayName: "My GitHub")],
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertEqual(snapshot.connections.count, 1)
        XCTAssertEqual(snapshot.connections[0].displayName, "My GitHub")
        XCTAssertEqual(snapshot.connections[0].id, connectionID.description)
    }

    func testEmptyInputsProduceEmptyLists() {
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [],
            connections: [],
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        XCTAssertTrue(snapshot.incoming.isEmpty)
        XCTAssertTrue(snapshot.outgoing.isEmpty)
        XCTAssertTrue(snapshot.drafts.isEmpty)
    }

    // MARK: - Outgoing field mapping

    func testOutgoingFieldsAreMappedCorrectly() throws {
        let outgoing = makeOutgoing(ci: .passing, unresolved: 0)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [outgoing],
            drafts: [],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        let row = try XCTUnwrap(snapshot.outgoing.first)
        XCTAssertEqual(row.id, "pr-out-1")
        XCTAssertEqual(row.repo, "acme/api")
        XCTAssertEqual(row.number, 20)
        XCTAssertEqual(row.title, "My PR")
        XCTAssertEqual(row.additions, 40)
        XCTAssertEqual(row.deletions, 10)
        XCTAssertEqual(row.files, 4)
        XCTAssertEqual(row.ageHours, 3.0)
    }

    // MARK: - Draft field mapping

    func testDraftFieldsAreMappedCorrectly() throws {
        let draft = makeDraft(ci: .running)
        let snapshot = WidgetSnapshot.from(
            incoming: [],
            outgoing: [],
            drafts: [draft],
            connections: makeConnections(),
            isSignedIn: true,
            lastUpdated: fixedDate
        )
        let row = try XCTUnwrap(snapshot.drafts.first)
        XCTAssertEqual(row.id, "pr-draft-1")
        XCTAssertEqual(row.repo, "acme/new")
        XCTAssertEqual(row.number, 30)
        XCTAssertEqual(row.title, "WIP draft")
        XCTAssertEqual(row.ci, .running)
        XCTAssertEqual(row.additions, 100)
        XCTAssertEqual(row.deletions, 20)
        XCTAssertEqual(row.files, 8)
    }
}

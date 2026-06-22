import SwiftUI
import XCTest
@testable import Hubber

/// Unit tests for `OutgoingReview.reviewVerdict` — the pure derivation that drives the
/// trailing review-status pill (the "review axis" paired with the leading CI rail).
final class ReviewVerdictTests: XCTestCase {
    private func reviewer(_ state: ReviewerState, _ login: String) -> Reviewer {
        Reviewer(user: CodeHostUser(login: login, initials: "XX", color: .gray), state: state)
    }

    private func review(
        reviewers: [Reviewer] = [],
        approvals: Int = 0,
        requiredApprovals: Int = 1
    ) -> OutgoingReview {
        OutgoingReview(
            id: "pr-1", repo: "acme/web", number: 1, title: "t", url: nil,
            ci: .passing, ciDetail: "", unresolved: 0,
            approvals: approvals, requiredApprovals: requiredApprovals,
            reviewers: reviewers, updatedAgoHours: 1, mergeable: true
        )
    }

    func testChangesRequestedWinsOverApprovals() {
        let r = review(
            reviewers: [reviewer(.approved, "a"), reviewer(.changesRequested, "b")],
            approvals: 1
        )
        XCTAssertEqual(r.reviewVerdict, .changesRequested)
    }

    func testApprovedWhenApprovalsMeetRequired() {
        let r = review(reviewers: [reviewer(.approved, "a")], approvals: 1, requiredApprovals: 1)
        XCTAssertEqual(r.reviewVerdict, .approved)
    }

    func testApprovedWhenRequiredIsZeroAndOneApproval() {
        // A repo with no approval rule: a single approval still reads as approved.
        let r = review(reviewers: [reviewer(.approved, "a")], approvals: 1, requiredApprovals: 0)
        XCTAssertEqual(r.reviewVerdict, .approved)
    }

    func testAwaitingWhenNoReviewersAndNoApprovals() {
        XCTAssertEqual(review().reviewVerdict, .awaitingReview)
    }

    func testInReviewWhenReviewersPendingButUndecided() {
        let r = review(reviewers: [reviewer(.pending, "a")], approvals: 0)
        XCTAssertEqual(r.reviewVerdict, .inReview)
    }

    func testInReviewWhenSomeApprovalsButNotEnough() {
        let r = review(reviewers: [reviewer(.approved, "a")], approvals: 1, requiredApprovals: 2)
        XCTAssertEqual(r.reviewVerdict, .inReview)
    }

    func testInReviewWhenCommentedOnly() {
        let r = review(reviewers: [reviewer(.commented, "a")], approvals: 0)
        XCTAssertEqual(r.reviewVerdict, .inReview)
    }

    func testPillLabelsAreStable() {
        XCTAssertEqual(ReviewVerdict.approved.pillLabel, "Approved")
        XCTAssertEqual(ReviewVerdict.changesRequested.pillLabel, "Changes")
        XCTAssertEqual(ReviewVerdict.inReview.pillLabel, "In review")
        XCTAssertEqual(ReviewVerdict.awaitingReview.pillLabel, "Awaiting")
    }
}

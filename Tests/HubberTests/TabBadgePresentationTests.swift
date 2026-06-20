import SwiftUI
import XCTest
@testable import Hubber

final class TabBadgePresentationTests: XCTestCase {
    private let baseDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Needs attention

    func testNeedsAttentionIncomingCountsAllItems() {
        let data = data(incoming: [incoming(id: "1"), incoming(id: "2"), incoming(id: "3")])

        let counts = TabBadgePresentation.counts(data: data, mode: .needsAttention)

        XCTAssertEqual(counts[.incoming], 3)
    }

    func testNeedsAttentionOutgoingCountsOnlyFailingOrUnresolved() {
        let data = data(outgoing: [
            outgoing(id: "healthy", ci: .passing, unresolved: 0),
            outgoing(id: "failing", ci: .failing, unresolved: 0),
            outgoing(id: "unresolved", ci: .passing, unresolved: 2),
            outgoing(id: "both", ci: .failing, unresolved: 1),
        ])

        let counts = TabBadgePresentation.counts(data: data, mode: .needsAttention)

        XCTAssertEqual(counts[.outgoing], 3)
    }

    func testNeedsAttentionDraftsCountsOnlyFailingCI() {
        let data = data(drafts: [
            draft(id: "pending", ci: .pending),
            draft(id: "passing", ci: .passing),
            draft(id: "failing", ci: .failing),
        ])

        let counts = TabBadgePresentation.counts(data: data, mode: .needsAttention)

        XCTAssertEqual(counts[.drafts], 1)
    }

    // MARK: - Total count

    func testTotalCountCountsEveryItemPerTab() {
        let data = data(
            incoming: [incoming(id: "i1"), incoming(id: "i2")],
            outgoing: [
                outgoing(id: "o1", ci: .passing, unresolved: 0),
                outgoing(id: "o2", ci: .passing, unresolved: 0),
                outgoing(id: "o3", ci: .passing, unresolved: 0),
            ],
            drafts: [draft(id: "d1", ci: .passing)]
        )

        let counts = TabBadgePresentation.counts(data: data, mode: .totalCount)

        XCTAssertEqual(counts[.incoming], 2)
        XCTAssertEqual(counts[.outgoing], 3)
        XCTAssertEqual(counts[.drafts], 1)
    }

    // MARK: - Empty

    func testEmptyDataYieldsZeroForEveryTabInBothModes() {
        let empty = HubberData(incoming: [], outgoing: [], drafts: [])

        for mode in TabBadgeMode.allCases {
            let counts = TabBadgePresentation.counts(data: empty, mode: mode)
            XCTAssertEqual(counts[.incoming, default: 0], 0, "incoming for \(mode)")
            XCTAssertEqual(counts[.outgoing, default: 0], 0, "outgoing for \(mode)")
            XCTAssertEqual(counts[.drafts, default: 0], 0, "drafts for \(mode)")
        }
    }

    // MARK: - Fixtures

    private func data(
        incoming: [IncomingReview] = [],
        outgoing: [OutgoingReview] = [],
        drafts: [DraftReview] = []
    ) -> HubberData {
        HubberData(incoming: incoming, outgoing: outgoing, drafts: drafts)
    }

    private func incoming(id: String) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: "acme/app",
            number: 1,
            title: "Needs review",
            url: nil,
            author: CodeHostUser(login: "a", initials: "A", color: .gray, avatarURL: nil),
            sloClockStart: baseDate,
            additions: 10,
            deletions: 2,
            files: 1
        )
    }

    private func outgoing(id: String, ci: PullRequestCI, unresolved: Int) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: "acme/api",
            number: 2,
            title: "Outgoing",
            url: nil,
            ci: ci,
            ciDetail: ci.rawValue,
            unresolved: unresolved,
            approvals: 1,
            requiredApprovals: 1,
            reviewers: [],
            updatedAgoHours: 1,
            mergeable: true
        )
    }

    private func draft(id: String, ci: PullRequestCI) -> DraftReview {
        DraftReview(
            id: id,
            repo: "acme/api",
            number: 3,
            title: "Draft",
            url: nil,
            ci: ci,
            ciDetail: ci.rawValue,
            commits: 1,
            updatedAt: baseDate
        )
    }
}

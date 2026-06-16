import XCTest
@testable import Hubber

@MainActor
final class AttentionStateTests: XCTestCase {

    // MARK: - Helpers

    private func makeSettings(sloEnabled: Bool = true, sloHours: Double = 4.0) -> SettingsStore {
        let suiteName = "AttentionStateTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let store = SettingsStore(defaults: defaults)
        store.sloEnabled = sloEnabled
        store.sloHours = sloHours
        return store
    }

    private func makeIncoming(
        id: String = UUID().uuidString,
        repo: String = "acme/ios",
        sloClockStart: Date = .hoursAgo(1)
    ) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: repo,
            number: 1,
            title: "PR",
            url: nil,
            author: .marisol,
            sloClockStart: sloClockStart,
            additions: 0,
            deletions: 0,
            files: 0
        )
    }

    private func makeOutgoing(
        id: String = UUID().uuidString,
        ci: PullRequestCI = .pending,
        unresolved: Int = 0
    ) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: "acme/api",
            number: 1,
            title: "PR",
            url: nil,
            ci: ci,
            ciDetail: "",
            unresolved: unresolved,
            approvals: 0,
            requiredApprovals: 1,
            reviewers: [],
            updatedAgoHours: 0,
            mergeable: false
        )
    }

    // MARK: - attentionCount + isAllGreen

    func testAllGreenWhenNoData() {
        let data = HubberData(incoming: [], outgoing: [], drafts: [])
        XCTAssertEqual(AttentionState.attentionCount(data: data), 0)
        XCTAssertTrue(AttentionState.isAllGreen(data: data))
    }

    func testIncomingReviewCountsAsAttention() {
        let data = HubberData(incoming: [makeIncoming()], outgoing: [], drafts: [])
        XCTAssertEqual(AttentionState.attentionCount(data: data), 1)
        XCTAssertFalse(AttentionState.isAllGreen(data: data))
    }

    func testFailingCIOutgoingCountsAsAttention() {
        let data = HubberData(incoming: [], outgoing: [makeOutgoing(ci: .failing)], drafts: [])
        XCTAssertEqual(AttentionState.attentionCount(data: data), 1)
    }

    func testRunningCIOutgoingDoesNotCount() {
        let data = HubberData(incoming: [], outgoing: [makeOutgoing(ci: .running)], drafts: [])
        XCTAssertEqual(AttentionState.attentionCount(data: data), 0)
    }

    func testPassingCIOutgoingWithNoUnresolvedDoesNotCount() {
        let data = HubberData(incoming: [], outgoing: [makeOutgoing(ci: .passing, unresolved: 0)], drafts: [])
        XCTAssertEqual(AttentionState.attentionCount(data: data), 0)
    }

    func testOutgoingWithUnresolvedCountsAsAttention() {
        let data = HubberData(incoming: [], outgoing: [makeOutgoing(ci: .passing, unresolved: 2)], drafts: [])
        XCTAssertEqual(AttentionState.attentionCount(data: data), 1)
    }

    func testPendingCIOutgoingDoesNotCount() {
        let data = HubberData(incoming: [], outgoing: [makeOutgoing(ci: .pending, unresolved: 0)], drafts: [])
        XCTAssertEqual(AttentionState.attentionCount(data: data), 0)
    }

    func testSamePRCountsOnce() {
        // Both failing CI and unresolved should count the PR only once.
        let data = HubberData(
            incoming: [],
            outgoing: [makeOutgoing(id: "pr-1", ci: .failing, unresolved: 3)],
            drafts: []
        )
        XCTAssertEqual(AttentionState.attentionCount(data: data), 1)
    }

    // MARK: - hasUrgentSLO

    func testHasUrgentSLOWhenWithin20PercentOfBudget() {
        // sloHours = 4h, 80% = 3.2h elapsed → urgent
        let settings = makeSettings(sloEnabled: true, sloHours: 4)
        let review = makeIncoming(sloClockStart: .hoursAgo(3.5))
        let data = HubberData(incoming: [review], outgoing: [], drafts: [])
        XCTAssertTrue(AttentionState.hasUrgentSLO(data: data, settings: settings))
    }

    func testNotUrgentSLOWhenUnder80Percent() {
        // sloHours = 4h, 50% = 2h elapsed → not urgent
        let settings = makeSettings(sloEnabled: true, sloHours: 4)
        let review = makeIncoming(sloClockStart: .hoursAgo(2))
        let data = HubberData(incoming: [review], outgoing: [], drafts: [])
        XCTAssertFalse(AttentionState.hasUrgentSLO(data: data, settings: settings))
    }

    func testHasUrgentSLOWhenOverdue() {
        // sloHours = 4h, 5h elapsed → overdue, definitely urgent
        let settings = makeSettings(sloEnabled: true, sloHours: 4)
        let review = makeIncoming(sloClockStart: .hoursAgo(5))
        let data = HubberData(incoming: [review], outgoing: [], drafts: [])
        XCTAssertTrue(AttentionState.hasUrgentSLO(data: data, settings: settings))
    }

    func testHasUrgentSLOFalseWhenSLODisabled() {
        let settings = makeSettings(sloEnabled: false, sloHours: 4)
        let review = makeIncoming(sloClockStart: .hoursAgo(5))
        let data = HubberData(incoming: [review], outgoing: [], drafts: [])
        XCTAssertFalse(AttentionState.hasUrgentSLO(data: data, settings: settings))
    }
}

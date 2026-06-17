import XCTest
@testable import Hubber

@MainActor
final class CrossProviderMixingTests: XCTestCase {
    private let baseDate = Date(timeIntervalSinceReferenceDate: 800_100_000)

    func testMCMIX01AggregateCombinesGitHubAndGitLabIncomingSortedBySLOClockStart() {
        let githubData = data(incoming: [
            incoming(
                id: "PR_kwgh_1",
                repo: "acme/web",
                number: 101,
                sloClockStart: baseDate.addingTimeInterval(20)
            ),
            incoming(
                id: "PR_kwgh_2",
                repo: "acme/web",
                number: 102,
                sloClockStart: baseDate.addingTimeInterval(40)
            ),
        ])
        let gitlabData = data(incoming: [
            incoming(
                id: "gid://gitlab/MergeRequest/42",
                repo: "acme/api",
                number: 42,
                sloClockStart: baseDate.addingTimeInterval(30)
            ),
        ])

        let aggregate = ConnectionAggregator.aggregate([githubData, gitlabData])

        XCTAssertEqual(aggregate.incoming.count, 3)
        XCTAssertEqual(
            aggregate.incoming.map(\.id),
            ["PR_kwgh_1", "gid://gitlab/MergeRequest/42", "PR_kwgh_2"]
        )
        XCTAssertEqual(
            Set(aggregate.incoming.map(\.id)),
            ["PR_kwgh_1", "PR_kwgh_2", "gid://gitlab/MergeRequest/42"]
        )
    }

    func testMCMIX02UrgentSLOIsDrivenByStaleGitHubReviewWithFreshGitLabReviewPresent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "CrossProviderMixingTests-\(UUID())"))
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.sloHours, 4.0)

        let githubData = data(incoming: [
            incoming(
                id: "PR_kwgh_stale",
                repo: "acme/web",
                number: 201,
                sloClockStart: .hoursAgo(6)
            ),
        ])
        let gitlabData = data(incoming: [
            incoming(
                id: "gid://gitlab/MergeRequest/77",
                repo: "acme/api",
                number: 77,
                sloClockStart: .hoursAgo(1)
            ),
        ])
        let aggregate = ConnectionAggregator.aggregate([githubData, gitlabData])

        XCTAssertTrue(AttentionState.hasUrgentSLO(data: aggregate, settings: settings))
    }

    func testMCMIX03GitLabNewReviewUsesIndependentBaselineFromGitHub() throws {
        let githubBaseline = ReviewSnapshot(incomingIDs: ["PR_kwgh_existing"], outgoing: [:])
        let gitlabBaseline = ReviewSnapshot(incomingIDs: ["gid://gitlab/MergeRequest/42"], outgoing: [:])
        let githubCurrent = data(incoming: [
            incoming(id: "PR_kwgh_existing", repo: "acme/web", number: 301),
        ])
        let gitlabCurrent = data(incoming: [
            incoming(id: "gid://gitlab/MergeRequest/42", repo: "acme/api", number: 42),
            incoming(id: "gid://gitlab/MergeRequest/99", repo: "acme/api", number: 99),
        ])

        let githubEvents = NotificationDiffer.events(
            previous: githubBaseline,
            current: githubCurrent,
            enabled: [.newReview]
        )
        let gitlabEvents = NotificationDiffer.events(
            previous: gitlabBaseline,
            current: gitlabCurrent,
            enabled: [.newReview]
        )

        XCTAssertTrue(githubEvents.isEmpty)
        XCTAssertEqual(gitlabEvents.count, 1)
        let event = try XCTUnwrap(gitlabEvents.first)
        XCTAssertEqual(event.type, .newReview)
        XCTAssertEqual(event.prID, "gid://gitlab/MergeRequest/99")
        XCTAssertEqual(githubBaseline.incomingIDs, ["PR_kwgh_existing"])
        XCTAssertFalse(githubBaseline.incomingIDs.contains("gid://gitlab/MergeRequest/99"))
    }

    func testMCMIX04AttentionCountAggregatesIncomingAndFailingCIAcrossProviders() {
        let githubData = data(incoming: [
            incoming(id: "PR_kwgh_needs_review", repo: "acme/web", number: 401),
        ])
        let gitlabData = data(outgoing: [
            outgoing(
                id: "gid://gitlab/MergeRequest/55",
                repo: "acme/api",
                number: 55,
                ci: .failing
            ),
        ])

        let aggregate = ConnectionAggregator.aggregate([githubData, gitlabData])

        XCTAssertEqual(AttentionState.attentionCount(data: aggregate), 2)
    }

    private func data(
        incoming: [IncomingReview] = [],
        outgoing: [OutgoingReview] = [],
        drafts: [DraftReview] = []
    ) -> HubberData {
        HubberData(incoming: incoming, outgoing: outgoing, drafts: drafts)
    }

    private func incoming(
        id: String,
        repo: String,
        number: Int,
        sloClockStart: Date? = nil
    ) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: repo,
            number: number,
            title: "Review \(number)",
            url: nil,
            author: .marisol,
            sloClockStart: sloClockStart ?? baseDate,
            additions: 10,
            deletions: 2,
            files: 3
        )
    }

    private func outgoing(
        id: String,
        repo: String,
        number: Int,
        ci: PullRequestCI = .passing
    ) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: repo,
            number: number,
            title: "Outgoing \(number)",
            url: nil,
            ci: ci,
            ciDetail: ci.rawValue,
            unresolved: 0,
            approvals: 0,
            requiredApprovals: 1,
            reviewers: [],
            updatedAgoHours: 1,
            mergeable: true
        )
    }
}

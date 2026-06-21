import Testing
@testable import Hubber

@Suite("AccessibilityText composed labels")
struct AccessibilityTextComposedTests {
    private func user(_ login: String) -> CodeHostUser {
        CodeHostUser(login: login, initials: "XX", color: .gray)
    }

    @Test("reviewers summary groups by state in canonical order")
    func reviewersSummary() {
        let reviewers = [
            Reviewer(user: user("a"), state: .approved),
            Reviewer(user: user("b"), state: .pending),
            Reviewer(user: user("c"), state: .approved),
        ]
        #expect(AccessibilityText.reviewersSummary(reviewers) == "3 reviewers: 2 approved, 1 review pending")
    }

    @Test("empty reviewers summary")
    func emptyReviewers() {
        #expect(AccessibilityText.reviewersSummary([]) == "no reviewers")
    }

    @Test("incoming row label with SLO")
    func incomingWithSLO() {
        let label = AccessibilityText.incomingRow(
            number: 1234, title: "Fix login crash", repo: "acme/app",
            authorLogin: "alice", sloEnabled: true, sloStatus: .red, sloText: "2h overdue"
        )
        #expect(label == "Pull request 1234, Fix login crash, in acme/app, by alice, review overdue, 2h overdue")
    }

    @Test("incoming row label without SLO")
    func incomingNoSLO() {
        let label = AccessibilityText.incomingRow(
            number: 7, title: "Tweak", repo: "acme/app",
            authorLogin: "bob", sloEnabled: false, sloStatus: nil, sloText: nil
        )
        #expect(label == "Pull request 7, Tweak, in acme/app, by bob")
    }

    @Test("outgoing row label with unresolved threads")
    func outgoing() {
        let label = AccessibilityText.outgoingRow(
            number: 42, title: "Add cache", repo: "acme/app", ci: .failing,
            unresolved: 1, reviewers: [Reviewer(user: user("a"), state: .changesRequested)]
        )
        #expect(label == "Pull request 42, Add cache, in acme/app, checks failing, 1 unresolved thread, 1 reviewer: 1 changes requested")
    }

    @Test("draft row label")
    func draft() {
        let label = AccessibilityText.draftRow(
            number: 9, title: "Spike", repo: "acme/app", ci: .running, commits: 6
        )
        #expect(label == "Draft pull request 9, Spike, in acme/app, checks running, 6 commits")
    }

    @Test("tab value pluralization")
    func tabValue() {
        #expect(AccessibilityText.tabValue(count: 0) == "0 items")
        #expect(AccessibilityText.tabValue(count: 1) == "1 item")
        #expect(AccessibilityText.tabValue(count: 5) == "5 items")
    }

    @Test("incoming row label appends PR size when present")
    func incomingWithSize() {
        let label = AccessibilityText.incomingRow(
            number: 7, title: "Tweak", repo: "acme/app",
            authorLogin: "bob", sloEnabled: false, sloStatus: nil, sloText: nil,
            additions: 120, deletions: 45
        )
        #expect(label == "Pull request 7, Tweak, in acme/app, by bob, 120 lines added, 45 removed")
    }

    @Test("outgoing row label appends PR size when present")
    func outgoingWithSize() {
        let label = AccessibilityText.outgoingRow(
            number: 42, title: "Add cache", repo: "acme/app", ci: .passing,
            unresolved: 0, reviewers: [], additions: 1240, deletions: 0
        )
        #expect(label == "Pull request 42, Add cache, in acme/app, checks passing, no reviewers, 1240 lines added")
    }

    @Test("draft row label omits PR size when zero")
    func draftNoSize() {
        let label = AccessibilityText.draftRow(
            number: 9, title: "Spike", repo: "acme/app", ci: .running, commits: 6,
            additions: 0, deletions: 0
        )
        #expect(label == "Draft pull request 9, Spike, in acme/app, checks running, 6 commits")
    }
}

@Suite("AccessibilityText size phrase")
struct AccessibilityTextSizeTests {
    @Test("both additions and deletions")
    func both() {
        #expect(AccessibilityText.sizePhrase(additions: 120, deletions: 45) == "120 lines added, 45 removed")
    }

    @Test("additions only")
    func additionsOnly() {
        #expect(AccessibilityText.sizePhrase(additions: 120, deletions: 0) == "120 lines added")
    }

    @Test("deletions only")
    func deletionsOnly() {
        #expect(AccessibilityText.sizePhrase(additions: 0, deletions: 45) == "45 lines removed")
    }

    @Test("both zero is nil")
    func bothZero() {
        #expect(AccessibilityText.sizePhrase(additions: 0, deletions: 0) == nil)
    }
}

@Suite("AccessibilityText atomic phrases")
struct AccessibilityTextAtomicTests {
    @Test("CI phrases")
    func ciPhrases() {
        #expect(AccessibilityText.ciPhrase(.passing) == "checks passing")
        #expect(AccessibilityText.ciPhrase(.failing) == "checks failing")
        #expect(AccessibilityText.ciPhrase(.running) == "checks running")
        #expect(AccessibilityText.ciPhrase(.pending) == "checks pending")
        #expect(AccessibilityText.ciPhrase(.noChecks) == "no checks")
    }

    @Test("Reviewer phrases")
    func reviewerPhrases() {
        #expect(AccessibilityText.reviewerPhrase(.approved) == "approved")
        #expect(AccessibilityText.reviewerPhrase(.changesRequested) == "changes requested")
        #expect(AccessibilityText.reviewerPhrase(.commented) == "commented")
        #expect(AccessibilityText.reviewerPhrase(.pending) == "review pending")
    }

    @Test("SLO phrases")
    func sloPhrases() {
        #expect(AccessibilityText.sloPhrase(.green) == "on track")
        #expect(AccessibilityText.sloPhrase(.amber) == "due soon")
        #expect(AccessibilityText.sloPhrase(.red) == "overdue")
    }
}

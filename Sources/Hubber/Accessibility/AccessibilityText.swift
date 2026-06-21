import Foundation

/// Pure, testable text that VoiceOver speaks. No SwiftUI/AppKit so it unit-tests cleanly.
enum AccessibilityText {
    static func ciPhrase(_ ci: PullRequestCI) -> String {
        switch ci {
        case .passing: "checks passing"
        case .failing: "checks failing"
        case .running: "checks running"
        case .pending: "checks pending"
        case .noChecks: "no checks"
        }
    }

    static func reviewerPhrase(_ state: ReviewerState) -> String {
        switch state {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .commented: "commented"
        case .pending: "review pending"
        }
    }

    static func sloPhrase(_ status: SLOStatus) -> String {
        switch status {
        case .green: "on track"
        case .amber: "due soon"
        case .red: "overdue"
        }
    }
}

extension AccessibilityText {
    /// Canonical state order so the summary is deterministic for tests + consistent for users.
    private static let reviewerOrder: [ReviewerState] = [.approved, .changesRequested, .commented, .pending]

    static func reviewersSummary(_ reviewers: [Reviewer]) -> String {
        guard !reviewers.isEmpty else { return "no reviewers" }
        let groups = reviewerOrder.compactMap { state -> String? in
            let n = reviewers.count(where: { $0.state == state })
            return n > 0 ? "\(n) \(reviewerPhrase(state))" : nil
        }
        let noun = reviewers.count == 1 ? "reviewer" : "reviewers"
        return "\(reviewers.count) \(noun): " + groups.joined(separator: ", ")
    }

    /// Spoken PR-size summary, or nil when there are no changed lines to announce.
    static func sizePhrase(additions: Int, deletions: Int) -> String? {
        switch (additions > 0, deletions > 0) {
        case (true, true): "\(additions) lines added, \(deletions) removed"
        case (true, false): "\(additions) lines added"
        case (false, true): "\(deletions) lines removed"
        case (false, false): nil
        }
    }

    static func incomingRow(
        number: Int, title: String, repo: String, authorLogin: String,
        sloEnabled: Bool, sloStatus: SLOStatus?, sloText: String?,
        additions: Int = 0, deletions: Int = 0
    ) -> String {
        var parts = ["Pull request \(number)", title, "in \(repo)", "by \(authorLogin)"]
        if sloEnabled, let sloStatus {
            parts.append("review \(sloPhrase(sloStatus))")
            if let sloText, !sloText.isEmpty { parts.append(sloText) }
        }
        if let size = sizePhrase(additions: additions, deletions: deletions) { parts.append(size) }
        return parts.joined(separator: ", ")
    }

    static func outgoingRow(
        number: Int, title: String, repo: String, ci: PullRequestCI,
        unresolved: Int, reviewers: [Reviewer],
        additions: Int = 0, deletions: Int = 0
    ) -> String {
        var parts = ["Pull request \(number)", title, "in \(repo)", ciPhrase(ci)]
        if unresolved > 0 {
            parts.append("\(unresolved) unresolved \(unresolved == 1 ? "thread" : "threads")")
        }
        parts.append(reviewersSummary(reviewers))
        if let size = sizePhrase(additions: additions, deletions: deletions) { parts.append(size) }
        return parts.joined(separator: ", ")
    }

    static func draftRow(
        number: Int, title: String, repo: String, ci: PullRequestCI, commits: Int,
        additions: Int = 0, deletions: Int = 0
    ) -> String {
        let commitText = "\(commits) \(commits == 1 ? "commit" : "commits")"
        var parts = ["Draft pull request \(number)", title, "in \(repo)", ciPhrase(ci), commitText]
        if let size = sizePhrase(additions: additions, deletions: deletions) { parts.append(size) }
        return parts.joined(separator: ", ")
    }

    static func tabValue(count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }
}

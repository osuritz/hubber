import Foundation

// MARK: - NotificationDiffer

enum NotificationDiffer {

    // MARK: - Public API

    /// Returns notification events by diffing `previous` snapshot against `current` data.
    /// Returns `[]` when `previous == nil` (initial load must never fire, #34).
    static func events(
        previous: ReviewSnapshot?,
        current: HubberData,
        enabled: Set<NotificationEventType>
    ) -> [NotificationEvent] {
        guard let previous else { return [] }
        let currentOutgoing = Dictionary(uniqueKeysWithValues: current.outgoing.map { ($0.id, $0) })
        return newReviewEvents(previous: previous, current: current, enabled: enabled)
            + outgoingChangeEvents(previous: previous, currentOutgoing: currentOutgoing, enabled: enabled)
            + prMergedEvents(previous: previous, currentOutgoing: currentOutgoing, enabled: enabled)
    }

    // MARK: - Snapshot builder

    /// Builds a `ReviewSnapshot` from the current `HubberData`.
    static func snapshot(from data: HubberData) -> ReviewSnapshot {
        let incomingIDs = Set(data.incoming.map(\.id))
        let outgoingSnaps = Dictionary(
            uniqueKeysWithValues: data.outgoing.map { pr -> (String, OutgoingSnapshot) in
                (pr.id, OutgoingSnapshot(from: pr))
            }
        )
        return ReviewSnapshot(incomingIDs: incomingIDs, outgoing: outgoingSnaps)
    }

    // MARK: - Private helpers

    private static func newReviewEvents(
        previous: ReviewSnapshot,
        current: HubberData,
        enabled: Set<NotificationEventType>
    ) -> [NotificationEvent] {
        guard enabled.contains(.newReview) else { return [] }
        return current.incoming
            .filter { !previous.incomingIDs.contains($0.id) }
            .map { review in
                NotificationEvent(
                    type: .newReview,
                    prID: review.id,
                    repo: review.repo,
                    number: review.number,
                    title: review.title,
                    url: review.url
                )
            }
    }

    private static func outgoingChangeEvents(
        previous: ReviewSnapshot,
        currentOutgoing: [String: OutgoingReview],
        enabled: Set<NotificationEventType>
    ) -> [NotificationEvent] {
        var result: [NotificationEvent] = []
        for (prID, prevSnap) in previous.outgoing {
            guard let currentPR = currentOutgoing[prID] else { continue }
            if let e = reviewApprovedEvent(prID: prID, prevSnap: prevSnap, currentPR: currentPR, enabled: enabled) {
                result.append(e)
            }
            if
                let e = changesRequestedEvent(
                    prID: prID, prevSnap: prevSnap, currentPR: currentPR, enabled: enabled
                ) {
                result.append(e)
            }
            if let e = ciFailedEvent(prID: prID, prevSnap: prevSnap, currentPR: currentPR, enabled: enabled) {
                result.append(e)
            }
        }
        return result
    }

    private static func reviewApprovedEvent(
        prID: String,
        prevSnap: OutgoingSnapshot,
        currentPR: OutgoingReview,
        enabled: Set<NotificationEventType>
    ) -> NotificationEvent? {
        guard enabled.contains(.reviewApproved) else { return nil }
        let newlyApproved = currentPR.reviewers.contains {
            $0.state == .approved && prevSnap.reviewerStates[$0.user.login] != ReviewerState.approved.rawValue
        }
        guard newlyApproved else { return nil }
        return NotificationEvent(
            type: .reviewApproved,
            prID: prID,
            repo: currentPR.repo,
            number: currentPR.number,
            title: currentPR.title,
            url: currentPR.url
        )
    }

    private static func changesRequestedEvent(
        prID: String,
        prevSnap: OutgoingSnapshot,
        currentPR: OutgoingReview,
        enabled: Set<NotificationEventType>
    ) -> NotificationEvent? {
        guard enabled.contains(.changesRequested) else { return nil }
        let newly = currentPR.reviewers.contains {
            $0.state == .changesRequested
                && prevSnap.reviewerStates[$0.user.login] != ReviewerState.changesRequested.rawValue
        }
        guard newly else { return nil }
        return NotificationEvent(
            type: .changesRequested,
            prID: prID,
            repo: currentPR.repo,
            number: currentPR.number,
            title: currentPR.title,
            url: currentPR.url
        )
    }

    private static func ciFailedEvent(
        prID: String,
        prevSnap: OutgoingSnapshot,
        currentPR: OutgoingReview,
        enabled: Set<NotificationEventType>
    ) -> NotificationEvent? {
        guard enabled.contains(.ciFailed) else { return nil }
        guard currentPR.ci == .failing, prevSnap.ci != PullRequestCI.failing.rawValue else { return nil }
        return NotificationEvent(
            type: .ciFailed,
            prID: prID,
            repo: currentPR.repo,
            number: currentPR.number,
            title: currentPR.title,
            url: currentPR.url
        )
    }

    private static func prMergedEvents(
        previous: ReviewSnapshot,
        currentOutgoing: [String: OutgoingReview],
        enabled: Set<NotificationEventType>
    ) -> [NotificationEvent] {
        guard enabled.contains(.prMerged) else { return [] }
        return previous.outgoing
            .filter { prID, prevSnap in
                currentOutgoing[prID] == nil && (prevSnap.mergeable || prevSnap.approved)
            }
            .map { prID, _ in
                // repo/number/title not stored in snapshot — enriched by coordinator if needed
                NotificationEvent(type: .prMerged, prID: prID, repo: "", number: 0, title: "", url: nil)
            }
    }
}

// MARK: - OutgoingSnapshot init

private extension OutgoingSnapshot {
    init(from pr: OutgoingReview) {
        let reviewerStates = Dictionary(uniqueKeysWithValues: pr.reviewers.map { ($0.user.login, $0.state.rawValue) })
        self.init(
            reviewerStates: reviewerStates,
            ci: pr.ci.rawValue,
            mergeable: pr.mergeable,
            approved: pr.approvals >= pr.requiredApprovals
        )
    }
}

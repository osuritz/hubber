import Foundation

enum ConnectionAggregator {
    static func aggregate(_ datas: [HubberData]) -> HubberData {
        var incomingByID: [String: IncomingReview] = [:]
        var outgoingByID: [String: OutgoingReview] = [:]
        var draftsByID: [String: DraftReview] = [:]

        for data in datas {
            for review in data.incoming {
                if let existing = incomingByID[review.id] {
                    if review.sloClockStart < existing.sloClockStart {
                        incomingByID[review.id] = review
                    }
                } else {
                    incomingByID[review.id] = review
                }
            }

            for review in data.outgoing where outgoingByID[review.id] == nil {
                outgoingByID[review.id] = review
            }

            for review in data.drafts where draftsByID[review.id] == nil {
                draftsByID[review.id] = review
            }
        }

        let incoming = incomingByID.values.sorted { lhs, rhs in
            if lhs.sloClockStart == rhs.sloClockStart {
                return lhs.id < rhs.id
            }
            return lhs.sloClockStart < rhs.sloClockStart
        }
        let outgoing = outgoingByID.values.sorted { lhs, rhs in
            if lhs.updatedAgoHours == rhs.updatedAgoHours {
                return lhs.id < rhs.id
            }
            return lhs.updatedAgoHours < rhs.updatedAgoHours
        }
        let drafts = draftsByID.values.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.id < rhs.id
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        return HubberData(incoming: incoming, outgoing: outgoing, drafts: drafts)
    }

    /// Aggregates only the visible connections' data. Pure — takes (id, data) pairs so it is
    /// testable without building `Connection`s / starting schedulers.
    static func aggregate(
        _ items: [(id: ConnectionID, data: HubberData)],
        visibility: ConnectionVisibility
    ) -> HubberData {
        aggregate(items.filter { visibility.isVisible($0.id) }.map(\.data))
    }

    /// Merges multiple per-connection baselines into a single union baseline for the diff.
    ///
    /// - Incoming IDs: plain set union.
    /// - Outgoing snapshots: if the same PR id appears in more than one baseline, OR the
    ///   `mergeable` and `approved` booleans, UNION the `reviewerStates` (a reviewer that has
    ///   advanced past `pending` in ANY baseline wins over `pending`), failing-wins for `ci`,
    ///   and keep-first the static metadata (`repo`/`number`/`title`/`url`).
    static func mergedBaseline(_ baselines: [ReviewSnapshot]) -> ReviewSnapshot {
        var incomingIDs = Set<String>()
        var outgoing: [String: OutgoingSnapshot] = [:]

        for baseline in baselines {
            incomingIDs.formUnion(baseline.incomingIDs)
            for (id, snapshot) in baseline.outgoing {
                if let existing = outgoing[id] {
                    outgoing[id] = mergeOutgoingSnapshots(existing, snapshot)
                } else {
                    outgoing[id] = snapshot
                }
            }
        }

        return ReviewSnapshot(incomingIDs: incomingIDs, outgoing: outgoing)
    }

    // MARK: - Private helpers

    /// Merges two `OutgoingSnapshot`s for the same PR id.
    /// OR the booleans; UNION the reviewerStates (non-pending wins); failing-wins for CI.
    /// Keep-first for static metadata.
    private static func mergeOutgoingSnapshots(
        _ first: OutgoingSnapshot,
        _ second: OutgoingSnapshot
    ) -> OutgoingSnapshot {
        var mergedReviewerStates = first.reviewerStates
        for (login, state) in second.reviewerStates {
            if let existing = mergedReviewerStates[login] {
                mergedReviewerStates[login] = Self.mostAdvancedReviewerState(existing, state)
            } else {
                mergedReviewerStates[login] = state
            }
        }
        return OutgoingSnapshot(
            reviewerStates: mergedReviewerStates,
            ci: (first.ci == PullRequestCI.failing.rawValue || second.ci == PullRequestCI.failing.rawValue)
                ? PullRequestCI.failing.rawValue
                : first.ci,
            mergeable: first.mergeable || second.mergeable,
            approved: first.approved || second.approved,
            repo: first.repo, // keep-first static metadata
            number: first.number,
            title: first.title,
            url: first.url
        )
    }

    /// Deterministic, order-independent tie-break for a reviewer observed in two baselines:
    /// the most-advanced state wins, so a reviewer that has progressed in ANY baseline is
    /// treated as already-observed and won't spuriously re-notify.
    private static func mostAdvancedReviewerState(_ a: String, _ b: String) -> String {
        reviewerStatePriority(a) >= reviewerStatePriority(b) ? a : b
    }

    private static func reviewerStatePriority(_ raw: String) -> Int {
        switch raw {
        case ReviewerState.changesRequested.rawValue: 3
        case ReviewerState.approved.rawValue: 2
        case ReviewerState.commented.rawValue: 1
        default: 0 // pending / unknown
        }
    }
}

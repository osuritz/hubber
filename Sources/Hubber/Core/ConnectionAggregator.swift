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

    /// Merges multiple per-connection baselines into a single union baseline for the diff.
    ///
    /// - Incoming IDs: plain set union.
    /// - Outgoing snapshots: if the same PR id appears in more than one baseline, OR the
    ///   `mergeable` and `approved` booleans, UNION the `reviewerStates` (a reviewer that has
    ///   advanced past `pending` in ANY baseline wins over `pending`), and keep-first the static
    ///   metadata (`repo`/`number`/`title`/`url`/`ci`).
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
    /// OR the booleans; UNION the reviewerStates (non-pending wins); keep-first static metadata.
    private static func mergeOutgoingSnapshots(
        _ first: OutgoingSnapshot,
        _ second: OutgoingSnapshot
    ) -> OutgoingSnapshot {
        var mergedReviewerStates = first.reviewerStates
        for (login, state) in second.reviewerStates {
            if let existingState = mergedReviewerStates[login] {
                // Non-pending state wins over pending
                let existingIsPending = existingState == ReviewerState.pending.rawValue
                if existingIsPending {
                    mergedReviewerStates[login] = state
                }
            } else {
                mergedReviewerStates[login] = state
            }
        }
        return OutgoingSnapshot(
            reviewerStates: mergedReviewerStates,
            ci: first.ci, // keep-first
            mergeable: first.mergeable || second.mergeable,
            approved: first.approved || second.approved,
            repo: first.repo, // keep-first static metadata
            number: first.number,
            title: first.title,
            url: first.url
        )
    }
}

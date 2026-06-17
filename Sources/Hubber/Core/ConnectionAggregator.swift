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

    static func mergedBaseline(_ baselines: [ReviewSnapshot]) -> ReviewSnapshot {
        var incomingIDs = Set<String>()
        var outgoing: [String: OutgoingSnapshot] = [:]

        for baseline in baselines {
            incomingIDs.formUnion(baseline.incomingIDs)
            for (id, snapshot) in baseline.outgoing where outgoing[id] == nil {
                outgoing[id] = snapshot
            }
        }

        return ReviewSnapshot(incomingIDs: incomingIDs, outgoing: outgoing)
    }
}

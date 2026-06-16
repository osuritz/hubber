import Foundation

/// Pure decision functions shared by RefreshScheduler and Stream B badge.
enum AttentionState {
    /// Returns the set of PR ids that need action: every incoming review
    /// plus outgoing with failing CI plus outgoing with unresolved > 0.
    @MainActor
    static func attentionItems(data: HubberData) -> Set<String> {
        var ids = Set<String>()
        for review in data.incoming {
            ids.insert(review.id)
        }
        for pr in data.outgoing {
            if pr.ci == .failing || pr.unresolved > 0 {
                ids.insert(pr.id)
            }
        }
        return ids
    }

    @MainActor
    static func attentionCount(data: HubberData, settings: SettingsStore) -> Int {
        attentionItems(data: data).count
    }

    @MainActor
    static func isAllGreen(data: HubberData, settings: SettingsStore) -> Bool {
        attentionCount(data: data, settings: settings) == 0
    }

    /// True when SLO is enabled and any incoming review has elapsed ≥ 80% of its SLO budget.
    @MainActor
    static func hasUrgentSLO(data: HubberData, settings: SettingsStore) -> Bool {
        guard settings.sloEnabled else { return false }
        return data.incoming.contains { review in
            let budget = settings.sloHours(for: review.repo)
            return review.assignedAgoHours >= 0.8 * budget
        }
    }
}

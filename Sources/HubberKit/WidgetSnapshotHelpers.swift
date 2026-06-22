import Foundation

// MARK: - Attention filter

/// Returns only rows where `needsAttention == true`. Pure, no side effects.
public func needsAttentionOnly(_ rows: [PRRowSnapshot]) -> [PRRowSnapshot] {
    rows.filter(\.needsAttention)
}

// MARK: - Sort order

public enum PRSortOrder: String, Sendable, CaseIterable, Equatable {
    /// Oldest by `ageHours` first — the PR that has been waiting longest sits at the top.
    case urgency
    /// Most-recently-updated first (smallest `ageHours`).
    case recentlyUpdated
    /// Largest diff (additions + deletions) first.
    case size
}

/// Returns `rows` sorted by `order`. Ties are broken by `id` for determinism.
public func sorted(_ rows: [PRRowSnapshot], by order: PRSortOrder) -> [PRRowSnapshot] {
    switch order {
    case .urgency:
        rows.sorted {
            $0.ageHours != $1.ageHours
                ? $0.ageHours > $1.ageHours
                : $0.id < $1.id
        }
    case .recentlyUpdated:
        rows.sorted {
            $0.ageHours != $1.ageHours
                ? $0.ageHours < $1.ageHours
                : $0.id < $1.id
        }
    case .size:
        rows.sorted {
            let lhs = $0.additions + $0.deletions
            let rhs = $1.additions + $1.deletions
            return lhs != rhs ? lhs > rhs : $0.id < $1.id
        }
    }
}

// MARK: - Staleness

public extension SnapshotMeta {
    /// Returns `true` when more than `threshold` seconds have elapsed since `lastUpdated`.
    func isStale(asOf now: Date = Date(), threshold: TimeInterval) -> Bool {
        now.timeIntervalSince(lastUpdated) > threshold
    }
}

import Foundation

/// Header label per spec decision #5: "All accounts" when all visible; "<Provider> · @login" when
/// exactly one visible; "N of M accounts" for a partial subset.
enum AccountHeaderLabel {
    static func text(ids: [ConnectionID], hidden: Set<ConnectionID>) -> String {
        let total = ids.count
        let visible = ids.filter { !hidden.contains($0) }
        if total == 0 { return "All accounts" }
        if visible.count == 1, let only = visible.first {
            return "\(only.providerDisplayName) · @\(only.login)"
        }
        if visible.count == total { return "All accounts" }
        return "\(visible.count) of \(total) accounts"
    }
}

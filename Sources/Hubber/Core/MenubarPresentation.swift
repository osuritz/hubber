import Foundation

/// Pure badge-count and state helpers for the menubar status item.
/// Contains no AppKit types so it can be unit-tested without a display.
enum MenubarPresentation {
    /// Returns the count to display as the badge, or nil (= no badge / icon-only).
    /// Zero counts collapse to nil so the badge disappears when there is nothing to act on.
    static func badgeCount(mode: BadgeMode, incomingCount: Int, attentionCount: Int) -> Int? {
        switch mode {
        case .off:
            nil
        case .incomingCount:
            incomingCount > 0 ? incomingCount : nil
        case .attentionNeeded:
            attentionCount > 0 ? attentionCount : nil
        }
    }

    struct State: Equatable {
        let badgeText: String?
        let isRefreshing: Bool
    }

    /// Maps raw values into the status item's view state.
    static func state(badgeCount: Int?, isRefreshing: Bool) -> State {
        State(badgeText: badgeCount.map(String.init), isRefreshing: isRefreshing)
    }
}

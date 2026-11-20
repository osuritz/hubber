import Foundation

struct RefreshContext: Equatable {
    var isRateLimited = false
    /// Seconds left in an outage back-off (5xx / network errors), if any.
    var unavailableRemaining: TimeInterval?
    var hasUrgentSLO = false
    var isPopoverOpen = false
    var isMachineIdle = false
    var isAllGreen = false
}

enum RefreshCadence {
    static func interval(for ctx: RefreshContext) -> TimeInterval {
        if ctx.isRateLimited {
            return 15 * 60
        }
        // Wake exactly when the back-off ends rather than a full interval later.
        if let remaining = ctx.unavailableRemaining {
            return max(remaining, 1)
        }
        if ctx.hasUrgentSLO {
            return 30
        }
        if ctx.isPopoverOpen {
            return 60
        }
        if ctx.isMachineIdle, ctx.isAllGreen {
            return 15 * 60
        }
        return 5 * 60
    }
}

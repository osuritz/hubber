import Foundation

struct RefreshContext: Equatable {
    var isRateLimited = false
    var hasUrgentSLO = false
    var isPopoverOpen = false
    var isMachineIdle = false
    var isAllGreen = false
}

enum RefreshCadence {
    static func interval(for ctx: RefreshContext) -> TimeInterval {
        if ctx.isRateLimited { return 15 * 60 }
        if ctx.hasUrgentSLO { return 30 }
        if ctx.isPopoverOpen { return 60 }
        if ctx.isMachineIdle, ctx.isAllGreen { return 15 * 60 }
        return 5 * 60
    }
}

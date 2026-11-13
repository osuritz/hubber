import Foundation

func elapsedText(hours: Double) -> String {
    let minutes = Int((hours * 60).rounded(.down))
    if minutes < 1 {
        return "just now"
    }
    if minutes < 60 {
        return "\(minutes)m ago"
    }
    if minutes < 24 * 60 {
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h) h \(m)m ago" : "\(h) h ago"
    }
    return "\(compactDaysText(minutes: minutes)) ago"
}

func remainingText(hours: Double) -> String {
    remainingDurationText(hours: hours, style: .compact)
}

func remainingDetailText(hours: Double) -> String {
    remainingDurationText(hours: hours, style: .detail)
}

private enum RemainingDurationStyle {
    case compact
    case detail
}

private func remainingDurationText(hours: Double, style: RemainingDurationStyle) -> String {
    let isOver = hours <= 0
    let suffix = isOver ? "over" : "left"
    let minutes = Int((abs(hours) * 60).rounded(.down))

    switch style {
    case .compact:
        return compactDurationText(minutes: minutes, suffix: suffix)
    case .detail:
        return detailedHoursText(minutes: minutes, suffix: suffix)
    }
}

private func compactDurationText(minutes: Int, suffix: String) -> String {
    // Keep exact minutes through roughly 1.5h; beyond that, round compact labels to half units.
    if minutes <= 91 {
        return "\(minutes)m \(suffix)"
    }

    if minutes >= 24 * 60 {
        return "\(compactDaysText(minutes: minutes)) \(suffix)"
    }

    return "\(compactHoursText(minutes: minutes)) \(suffix)"
}

private func detailedHoursText(minutes: Int, suffix: String) -> String {
    if minutes < 60 {
        return "\(minutes)m \(suffix)"
    }
    let h = minutes / 60
    let m = minutes % 60
    return m > 0 ? "\(h) h \(m)m \(suffix)" : "\(h) h \(suffix)"
}

private func compactHoursText(minutes: Int) -> String {
    let halfHours = max(1, Int((Double(minutes) / 30).rounded()))
    return compactHalfUnitText(halfUnits: halfHours, unit: "h")
}

private func compactDaysText(minutes: Int) -> String {
    let halfDays = max(1, Int((Double(minutes) / Double(12 * 60)).rounded()))
    return compactHalfUnitText(halfUnits: halfDays, unit: "d")
}

private func compactHalfUnitText(halfUnits: Int, unit: String) -> String {
    let wholeUnits = halfUnits / 2
    let hasHalfUnit = halfUnits.isMultiple(of: 2) == false

    if hasHalfUnit {
        return wholeUnits > 0 ? "\(wholeUnits) ½ \(unit)" : "½ \(unit)"
    }

    return "\(wholeUnits) \(unit)"
}

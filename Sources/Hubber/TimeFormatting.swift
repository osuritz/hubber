import Foundation

func elapsedText(hours: Double) -> String {
    let minutes = Int((hours * 60).rounded(.down))
    if minutes < 1 { return "just now" }
    if minutes < 60 { return "\(minutes)m ago" }
    if minutes < 24 * 60 {
        let h = minutes / 60
        let m = minutes % 60
        return m > 0 ? "\(h) h \(m)m ago" : "\(h) h ago"
    }
    return "\(minutes / (24 * 60))d ago"
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
    if minutes <= 91 {
        return "\(minutes)m \(suffix)"
    }

    return "\(compactHoursText(minutes: minutes)) \(suffix)"
}

private func detailedHoursText(minutes: Int, suffix: String) -> String {
    if minutes < 60 { return "\(minutes)m \(suffix)" }
    let h = minutes / 60
    let m = minutes % 60
    return m > 0 ? "\(h) h \(m)m \(suffix)" : "\(h) h \(suffix)"
}

private func compactHoursText(minutes: Int) -> String {
    let halfHours = max(1, Int((Double(minutes) / 30).rounded()))
    let wholeHours = halfHours / 2
    let hasHalfHour = halfHours.isMultiple(of: 2) == false

    if hasHalfHour {
        return wholeHours > 0 ? "\(wholeHours) ½ h" : "½ h"
    }

    return "\(wholeHours) h"
}

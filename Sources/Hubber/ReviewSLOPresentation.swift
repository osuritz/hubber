import Foundation

enum ReviewSLOPresentation {
    static let settingsSectionTitle = "Incoming Reviews"
    static let title = "Review SLO"
    static let subtitle = "Show timing badges for incoming review requests."
    static let windowLabel = "Review window"
    static let thresholdHelp = "Reviews are flagged amber at 50% and red at 100% of this budget."

    static func footerText(isEnabled: Bool, hours: Double) -> String {
        isEnabled ? "SLO \(Int(hours))h" : "SLO off"
    }

    /// Returns a footer string like "Rate limited — next refresh in 15m".
    static func rateLimitFooter(secondsRemaining: TimeInterval) -> String {
        let minutes = max(1, Int((secondsRemaining / 60).rounded(.up)))
        return "Rate limited — next refresh in \(minutes)m"
    }

    /// Returns a footer string like "GitHub unavailable — retrying in 5m" ("in 20s" under a minute).
    static func outageFooter(providerName: String, secondsRemaining: TimeInterval) -> String {
        let seconds = max(1, Int(secondsRemaining.rounded(.up)))
        let wait = seconds < 60 ? "\(seconds)s" : "\(Int((secondsRemaining / 60).rounded(.up)))m"
        return "\(providerName) unavailable — retrying in \(wait)"
    }
}

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

    /// Returns a footer string like "Rate limited — next refresh in 15m", or "GitHub rate limited — ..." when
    /// `subject` names the affected account (or "2 accounts" when several are).
    static func rateLimitFooter(subject: String? = nil, secondsRemaining: TimeInterval) -> String {
        let minutes = max(1, Int((secondsRemaining / 60).rounded(.up)))
        let prefix = subject.map { "\($0) rate limited" } ?? "Rate limited"
        return "\(prefix) — next refresh in \(minutes)m"
    }

    /// Returns a footer string like "GitHub unavailable — retrying in 5m" ("in 20s" under a minute).
    static func outageFooter(providerName: String, secondsRemaining: TimeInterval) -> String {
        let seconds = max(1, Int(secondsRemaining.rounded(.up)))
        let wait = seconds < 60 ? "\(seconds)s" : "\(Int((secondsRemaining / 60).rounded(.up)))m"
        return "\(providerName) unavailable — retrying in \(wait)"
    }
}

enum ReviewSLOPresentation {
    static let settingsSectionTitle = "Incoming Reviews"
    static let title = "Review SLO"
    static let subtitle = "Show timing badges for incoming review requests."
    static let windowLabel = "Review window"
    static let thresholdHelp = "Reviews are flagged amber at 50% and red at 100% of this budget."

    static func footerText(isEnabled: Bool, hours: Double) -> String {
        isEnabled ? "SLO \(Int(hours))h" : "SLO off"
    }
}

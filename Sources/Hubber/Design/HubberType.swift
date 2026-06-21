import SwiftUI

// MARK: - HubberType — SF Pro type scale

/// All typographic roles used in Hubber, transcribed from tokens.jsx TYPE.
/// Use `.system(size:weight:design:)` — no custom fonts; SF Pro / SF Mono only.
enum HubberType {

    // MARK: Type Roles

    /// PR title — 13 / Medium
    static let title: Font = .system(size: 13, weight: .medium)

    /// Secondary line text — 11 / Regular
    static let secondary: Font = .system(size: 11, weight: .regular)

    /// SLO pill — 11 / Medium · monospaced digits
    static let sloPill = Font.system(size: 11, weight: .medium).monospacedDigit()

    /// CI detail text — 11 / Regular
    static let ciDetail: Font = .system(size: 11, weight: .regular)

    /// Log viewer — 11 / SF Mono
    static let log: Font = .system(size: 11, weight: .regular, design: .monospaced)

    /// Section header — 11 / Semibold · UPPERCASE · +0.4 tracking
    /// Note: uppercase transform and +0.4 tracking must be applied at the call site.
    static let section: Font = .system(size: 11, weight: .semibold)

    /// Footer text — 11 / Regular
    static let footer: Font = .system(size: 11, weight: .regular)

    // MARK: Supplemental Roles (used in rows / header but not named in TYPE)

    /// PR number prefix — 11 / Regular · monospaced (SF Mono feel)
    static let prNumber: Font = .system(size: 11, weight: .regular, design: .monospaced)

    /// Header title — 15 / Semibold
    static let headerTitle: Font = .system(size: 15, weight: .semibold)

    /// Settings row label — 12.5 / Regular
    static let settingsLabel: Font = .system(size: 12.5, weight: .regular)

    /// Settings subtext — 11 / Regular
    static let settingsSub: Font = .system(size: 11, weight: .regular)

    /// Badge / count chip — 10 / Semibold · monospaced digits
    static let badge = Font.system(size: 10, weight: .semibold).monospacedDigit()

    /// PR size +/- indicator — 11 / Regular · monospaced digits (aligns the +/- counts)
    static let prSize = Font.system(size: 11, weight: .regular).monospacedDigit()

    // MARK: Size Constants

    /// Point sizes for each role, used in tests.
    enum PointSize {
        static let title: CGFloat = 13
        static let secondary: CGFloat = 11
        static let sloPill: CGFloat = 11
        static let ciDetail: CGFloat = 11
        static let log: CGFloat = 11
        static let section: CGFloat = 11
        static let footer: CGFloat = 11
    }
}

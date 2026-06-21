import SwiftUI

// MARK: - HubberFont — @ScaledMetric-backed typographic roles

/// Scalable replacement for HubberType's fixed-size fonts.
///
/// Sizes scale with the environment's Dynamic Type via `@ScaledMetric`.
/// macOS has no system Dynamic Type slider today, so this is primarily
/// future-proofing and Bold Text support — it is a visual no-op at the
/// current (factor 1.0) accessibility setting.
///
/// ## Migration guide
/// Replace `.font(HubberType.xxx)` with `.hubberFont(.xxx)`.
/// Roles that require monospaced digits must chain `.monospacedDigit()` at
/// the call site (sloPill, badge). Roles with SF Mono design (log, prNumber)
/// carry `design: .monospaced` automatically inside the modifier.
enum HubberFont {

    // MARK: Role

    enum Role {
        case title
        case secondary
        case sloPill
        case ciDetail
        case log
        case section
        case footer
        case prNumber
        case headerTitle
        case settingsLabel
        case settingsSub
        case badge

        /// Base point size — must stay pixel-identical to the matching
        /// HubberType constant so migration is a visual no-op.
        var base: CGFloat {
            switch self {
            case .title: 13
            case .headerTitle: 15
            case .settingsLabel: 12.5
            case .badge: 10
            default: 11
            }
        }

        /// Font weight — matches the HubberType definition for each role.
        var weight: Font.Weight {
            switch self {
            case .title: .medium
            case .sloPill: .medium
            case .section, .headerTitle, .badge: .semibold
            default: .regular
            }
        }

        /// Font design — carries SF Mono for roles that use `design: .monospaced`.
        /// Roles using `.monospacedDigit()` (sloPill, badge) are handled at the
        /// call site, not here; they use the default proportional design.
        var design: Font.Design {
            switch self {
            case .log, .prNumber: .monospaced
            default: .default
            }
        }

        /// Dynamic Type text style used as the scaling reference for `@ScaledMetric`.
        var textStyle: Font.TextStyle {
            switch self {
            case .headerTitle: .headline
            case .title, .settingsLabel: .body
            default: .caption
            }
        }
    }

    // MARK: scaledSize

    /// Returns `base * factor`. The factor comes from `@ScaledMetric` at the
    /// call site; here it is exposed as a testable pure function.
    static func scaledSize(base: CGFloat, factor: CGFloat) -> CGFloat {
        base * factor
    }

    // MARK: weight(for:bold:)

    /// Resolves the effective `Font.Weight` for a role, optionally stepping one
    /// level heavier when the system Bold Text accessibility setting is active.
    ///
    /// **Invariant**: when `bold == false` the return value is identical to
    /// `role.weight` — a visual no-op that preserves today's exact appearance.
    ///
    /// Bold step-up table:
    /// - regular    → semibold
    /// - medium     → semibold
    /// - semibold   → bold
    /// - bold       → heavy
    /// - (anything else stays unchanged)
    static func weight(for role: Role, bold: Bool) -> Font.Weight {
        guard bold else { return role.weight }
        switch role.weight {
        case .regular: return .semibold
        case .medium: return .semibold
        case .semibold: return .bold
        case .bold: return .heavy
        default: return role.weight
        }
    }
}

// MARK: - HubberFontModifier

private struct HubberFontModifier: ViewModifier {
    let role: HubberFont.Role
    @ScaledMetric private var scaled: CGFloat
    @Environment(\.legibilityWeight) private var legibilityWeight

    init(role: HubberFont.Role) {
        self.role = role
        _scaled = ScaledMetric(wrappedValue: role.base, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        let isBold = legibilityWeight == .bold
        let resolvedWeight = HubberFont.weight(for: role, bold: isBold)
        return content.font(.system(size: scaled, weight: resolvedWeight, design: role.design))
    }
}

// MARK: - View extension

extension View {
    /// Apply a typographic role that scales with Dynamic Type.
    ///
    /// For roles that require monospaced digits (sloPill, badge), chain
    /// `.monospacedDigit()` after this modifier.
    func hubberFont(_ role: HubberFont.Role) -> some View {
        modifier(HubberFontModifier(role: role))
    }
}

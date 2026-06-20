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
}

// MARK: - HubberFontModifier

private struct HubberFontModifier: ViewModifier {
    let role: HubberFont.Role
    @ScaledMetric private var scaled: CGFloat

    init(role: HubberFont.Role) {
        self.role = role
        _scaled = ScaledMetric(wrappedValue: role.base, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaled, weight: role.weight, design: role.design))
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

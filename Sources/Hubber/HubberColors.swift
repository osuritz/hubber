import AppKit
import SwiftUI

// MARK: - Legacy named colors (kept for any call sites that use them directly)

extension Color {
    static let hubberSuccess = HubberDesign.ciPassing
    static let hubberWarning = HubberDesign.sloAmber.fg
    static let hubberError = HubberDesign.error
}

// MARK: - HubberAppearance (re-pointed at HubberDesign tokens)

//
// All helpers are kept so existing call sites continue to compile unchanged.

enum HubberAppearance {
    static func panelFill(for colorScheme: ColorScheme) -> Color {
        // Dark mode relies on the popover material alone; light mode needs a steadier backing for contrast.
        colorScheme == .dark ? .clear : Color(nsColor: .windowBackgroundColor).opacity(0.78)
    }

    static func badgeFill(isActive: Bool, for colorScheme: ColorScheme) -> Color {
        switch (colorScheme, isActive) {
        case (.dark, true): .white.opacity(0.16)
        case (.dark, false): .white.opacity(0.10)
        case (_, true): .black.opacity(0.075)
        case (_, false): .black.opacity(0.045)
        }
    }

    static func chipFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.06)
    }

    static func avatarStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.15) : .white.opacity(0.70)
    }
}

import AppKit
import SwiftUI

// MARK: - Legacy named colors (kept for any call sites that use them directly)

extension Color {
    static let hubberSuccess = HubberDesign.ciPassing
    static let hubberWarning = Color(light: "#FF9500", dark: "#FFA00A")
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

    static func controlGroupFill(for colorScheme: ColorScheme) -> Color {
        HubberDesign.ctrlTrack
    }

    static func selectedControlFill(for colorScheme: ColorScheme) -> Color {
        HubberDesign.ctrlThumb
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

    static func hairline(for colorScheme: ColorScheme) -> Color {
        HubberDesign.sep
    }

    static func avatarStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.15) : .white.opacity(0.70)
    }

    static func statusDotStroke(for colorScheme: ColorScheme) -> Color {
        HubberDesign.materialSolid
    }

    static func controlShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.25) : .black.opacity(0.12)
    }

    // MARK: SLO Helpers — now delegating to HubberDesign

    static func sloColor(_ status: SLOStatus, for colorScheme: ColorScheme) -> Color {
        HubberDesign.sloForeground(status)
    }

    static func sloFillOpacity(_ status: SLOStatus, for colorScheme: ColorScheme) -> Double {
        // Kept for legacy callers — the real fill color is now in HubberDesign.sloBackground(_:)
        if colorScheme == .dark {
            return status == .red ? 0.18 : 0.16
        }
        return status == .red ? 0.12 : 0.10
    }

    static func sloStrokeOpacity(_ status: SLOStatus, for colorScheme: ColorScheme) -> Double {
        if colorScheme == .dark {
            return status == .red ? 0.45 : 0.40
        }
        return status == .red ? 0.24 : 0.22
    }

    static func sloDotShadowOpacity(for colorScheme: ColorScheme) -> Double {
        colorScheme == .dark ? 0.65 : 0.28
    }
}

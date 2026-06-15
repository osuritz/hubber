import AppKit
import SwiftUI

extension Color {
    static let hubberSuccess = Color(red: 0.25, green: 0.73, blue: 0.31)
    static let hubberWarning = Color(red: 0.89, green: 0.70, blue: 0.25)
    static let hubberError = Color(red: 1.00, green: 0.48, blue: 0.45)
}

enum HubberAppearance {
    static func panelFill(for colorScheme: ColorScheme) -> Color {
        // Dark mode relies on the popover material alone; light mode needs a steadier backing for contrast.
        colorScheme == .dark ? .clear : Color(nsColor: .windowBackgroundColor).opacity(0.78)
    }

    static func controlGroupFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.055)
    }

    static func selectedControlFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.16) : .white.opacity(0.68)
    }

    static func badgeFill(isActive: Bool, for colorScheme: ColorScheme) -> Color {
        switch (colorScheme, isActive) {
        case (.dark, true):
            .white.opacity(0.16)
        case (.dark, false):
            .white.opacity(0.10)
        case (_, true):
            .black.opacity(0.075)
        case (_, false):
            .black.opacity(0.045)
        }
    }

    static func chipFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.06)
    }

    static func hairline(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.08)
    }

    static func avatarStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.15) : .white.opacity(0.70)
    }

    static func statusDotStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.17) : .white.opacity(0.85)
    }

    static func controlShadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .black.opacity(0.25) : .black.opacity(0.12)
    }

    static func sloColor(_ status: SLOStatus, for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            switch status {
            case .green: .hubberSuccess
            case .amber: .hubberWarning
            case .red: .hubberError
            }
        } else {
            switch status {
            case .green: Color(red: 0.12, green: 0.56, blue: 0.20)
            case .amber: Color(red: 0.70, green: 0.43, blue: 0.00)
            case .red: Color(red: 0.82, green: 0.23, blue: 0.18)
            }
        }
    }

    static func sloFillOpacity(_ status: SLOStatus, for colorScheme: ColorScheme) -> Double {
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

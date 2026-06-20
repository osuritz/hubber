import AppKit
import SwiftUI

// MARK: - Light/Dark Color Helper

extension Color {
    /// Create a Color that resolves to different values in light and dark appearances.
    /// Backed by NSColor's dynamic provider so it correctly follows system appearance changes.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua:
                dark
            default:
                light
            }
        })
    }

    /// Convenience initializer using hex RGBA strings.
    init(light hexLight: String, dark hexDark: String) {
        self.init(
            light: NSColor(hex: hexLight),
            dark: NSColor(hex: hexDark)
        )
    }
}

extension NSColor {
    /// Parse a hex string (#RRGGBB or #RRGGBBAA) or rgba(r,g,b,a) CSS string.
    convenience init(hex: String) {
        // Handle rgba(r,g,b,a) CSS format
        if hex.hasPrefix("rgba(") {
            let inner = hex.dropFirst(5).dropLast(1)
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if
                parts.count == 4,
                let r = Double(parts[0]),
                let g = Double(parts[1]),
                let b = Double(parts[2]),
                let a = Double(parts[3]) {
                self.init(
                    srgbRed: r / 255.0,
                    green: g / 255.0,
                    blue: b / 255.0,
                    alpha: a
                )
                return
            }
        }

        // Handle #RRGGBB or #RRGGBBAA
        var clean = hex
        if clean.hasPrefix("#") { clean = String(clean.dropFirst()) }
        if clean.count == 3 {
            clean = String(clean.flatMap { c in [c, c] })
        }
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        if clean.count == 6 {
            self.init(
                srgbRed: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0,
                alpha: 1.0
            )
        } else if clean.count == 8 {
            self.init(
                srgbRed: Double((value >> 24) & 0xFF) / 255.0,
                green: Double((value >> 16) & 0xFF) / 255.0,
                blue: Double((value >> 8) & 0xFF) / 255.0,
                alpha: Double(value & 0xFF) / 255.0
            )
        } else {
            // Fallback: magenta so it's obvious something is wrong
            self.init(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        }
    }
}

// MARK: - SLO Token Group

struct SLOTokenGroup {
    let fg: Color
    let bg: Color
    let border: Color
}

// MARK: - HubberDesign — single source of truth

/// All semantic color tokens transcribed from tokens.jsx PALETTE / T().
/// Every Color value resolves correctly in both light and dark appearance.
enum HubberDesign {

    // MARK: SLO Tokens

    static let sloGreen = SLOTokenGroup(
        fg: Color(light: "#1F7935", dark: "#30D158"), // a11y: light #248A3D→#1F7935 (3.69→4.59:1 on green bg)
        bg: Color(light: "rgba(52,199,89,0.13)", dark: "rgba(48,209,88,0.16)"),
        border: Color(light: "rgba(52,199,89,0.30)", dark: "rgba(48,209,88,0.34)")
    )

    static let sloAmber = SLOTokenGroup(
        fg: Color(light: "#9A5B00", dark: "#FFA00A"),
        bg: Color(light: "rgba(255,149,0,0.14)", dark: "rgba(255,159,10,0.16)"),
        border: Color(light: "rgba(255,149,0,0.32)", dark: "rgba(255,159,10,0.34)")
    )

    static let sloRed = SLOTokenGroup(
        fg: Color(light: "#CE0014", dark: "#FF7067"), // a11y: light #D70015→#CE0014 (4.27→4.58:1); dark #FF6E66→#FF7067 (4.50→4.55:1)
        bg: Color(light: "rgba(255,59,48,0.12)", dark: "rgba(255,69,58,0.18)"),
        border: Color(light: "rgba(255,59,48,0.30)", dark: "rgba(255,69,58,0.36)")
    )

    static func sloTokens(for status: SLOStatus) -> SLOTokenGroup {
        switch status {
        case .green: sloGreen
        case .amber: sloAmber
        case .red: sloRed
        }
    }

    // MARK: CI State Colors

    static let ciPassing = Color(light: "#248A3D", dark: "#30D158")
    static let ciFailing = Color(light: "#D70015", dark: "#FF453A")
    /// neutral — not an action signal
    static let ciRunning = Color(light: "#8E8E93", dark: "#98989D")
    static let ciPending = Color(light: "#8E8E93", dark: "#98989D")
    /// muted neutral — no CI configured/run (distinct from pending)
    static let ciNoChecks = Color(light: "#C7C7CC", dark: "#5A5A5E")

    static func ciColor(for ci: PullRequestCI) -> Color {
        switch ci {
        case .passing: ciPassing
        case .failing: ciFailing
        case .running: ciRunning
        case .pending: ciPending
        case .noChecks: ciNoChecks
        }
    }

    // MARK: Reviewer State Dot Colors

    static let rvApproved = Color(light: "#34C759", dark: "#30D158")
    static let rvChanges = Color(light: "#FF3B30", dark: "#FF453A")
    static let rvComment = Color(light: "#007AFF", dark: "#0A84FF")
    /// hollow ring — no fill, use border only
    static let rvPending = Color(light: "#C7C7CC", dark: "#5A5A5E")

    static func reviewerColor(for state: ReviewerState) -> Color? {
        switch state {
        case .approved: rvApproved
        case .changesRequested: rvChanges
        case .commented: rvComment
        case .pending: nil // hollow ring, no fill
        }
    }

    // MARK: System Accent / Error

    static let accent = Color(light: "#007AFF", dark: "#0A84FF")
    static let error = Color(light: "#D70015", dark: "#FF453A")

    // MARK: Action-Signal Row Treatment

    static let signalTint = Color(light: "rgba(255,59,48,0.045)", dark: "rgba(255,69,58,0.07)")
    static let signalAccent = Color(light: "#FF3B30", dark: "#FF453A")

    // MARK: Material / Background

    /// Translucent vibrancy-style material color (used for spec chips needing opacity)
    static let materialSolid = Color(light: "#f6f6f8", dark: "#262628")

    // MARK: Text

    static let text = Color(light: "rgba(0,0,0,0.85)", dark: "rgba(255,255,255,0.92)")
    static let text2 = Color(
        light: "rgba(60,60,67,0.72)",
        dark: "rgba(235,235,245,0.58)"
    ) // a11y: light alpha 0.56→0.72 (3.03→4.56:1 on materialSolid)
    static let text3 = Color(light: "rgba(60,60,67,0.32)", dark: "rgba(235,235,245,0.32)")

    // MARK: Lines + Fills

    static let sep = Color(light: "rgba(0,0,0,0.08)", dark: "rgba(255,255,255,0.10)")
    static let sepStrong = Color(light: "rgba(0,0,0,0.12)", dark: "rgba(255,255,255,0.14)")
    static let fill = Color(light: "rgba(0,0,0,0.035)", dark: "rgba(255,255,255,0.06)")
    static let fillHover = Color(light: "rgba(0,0,0,0.05)", dark: "rgba(255,255,255,0.09)")

    // MARK: Controls

    static let ctrlTrack = Color(light: "rgba(0,0,0,0.055)", dark: "rgba(255,255,255,0.08)")
    static let ctrlThumb = Color(light: "#ffffff", dark: "rgba(120,120,128,0.44)")

    // MARK: Legacy Compatibility Helpers

    // These re-implement the HubberAppearance helpers in terms of HubberDesign tokens
    // so existing call sites continue to compile unchanged.

    static func sloForeground(_ status: SLOStatus) -> Color {
        sloTokens(for: status).fg
    }

    static func sloBackground(_ status: SLOStatus) -> Color {
        sloTokens(for: status).bg
    }

    static func sloBorder(_ status: SLOStatus) -> Color {
        sloTokens(for: status).border
    }
}

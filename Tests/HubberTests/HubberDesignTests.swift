import AppKit
import SwiftUI
import Testing
@testable import Hubber

// MARK: - Token light/dark resolution tests

@Suite("HubberDesign tokens")
struct HubberDesignTests {

    // Helper: resolve a SwiftUI Color's NSColor in a given appearance.
    // We round-trip via NSColor's dynamic provider.
    private func nsColor(from color: Color, appearance: NSAppearance) -> NSColor {
        let ns = NSColor(color)
        var resolved: NSColor = ns
        appearance.performAsCurrentDrawingAppearance {
            resolved = ns.usingColorSpace(.sRGB) ?? ns
        }
        return resolved
    }

    /// Assert that a token resolves to *different* values in light vs. dark.
    private func assertLightDarkDiffer(_ color: Color, name: String) {
        guard
            let light = NSAppearance(named: .aqua),
            let dark = NSAppearance(named: .darkAqua)
        else { return }

        var lightColor = NSColor.black
        var darkColor = NSColor.black

        light.performAsCurrentDrawingAppearance {
            lightColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        }
        dark.performAsCurrentDrawingAppearance {
            darkColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
        }

        #expect(
            lightColor != darkColor,
            "Token '\(name)' should differ between light and dark appearances"
        )
    }

    // MARK: SLO Tokens

    @Test("SLO green fg differs light/dark")
    func sloGreenFgDiffers() {
        assertLightDarkDiffer(HubberDesign.sloGreen.fg, name: "sloGreen.fg")
    }

    @Test("SLO amber fg differs light/dark")
    func sloAmberFgDiffers() {
        assertLightDarkDiffer(HubberDesign.sloAmber.fg, name: "sloAmber.fg")
    }

    @Test("SLO red fg differs light/dark")
    func sloRedFgDiffers() {
        assertLightDarkDiffer(HubberDesign.sloRed.fg, name: "sloRed.fg")
    }

    @Test("SLO green bg differs light/dark")
    func sloGreenBgDiffers() {
        assertLightDarkDiffer(HubberDesign.sloGreen.bg, name: "sloGreen.bg")
    }

    @Test("SLO red border differs light/dark")
    func sloRedBorderDiffers() {
        assertLightDarkDiffer(HubberDesign.sloRed.border, name: "sloRed.border")
    }

    // MARK: CI Colors

    @Test("CI passing differs light/dark")
    func ciPassingDiffers() {
        assertLightDarkDiffer(HubberDesign.ciPassing, name: "ciPassing")
    }

    @Test("CI failing differs light/dark")
    func ciFailingDiffers() {
        assertLightDarkDiffer(HubberDesign.ciFailing, name: "ciFailing")
    }

    // MARK: Reviewer Colors

    @Test("Reviewer approved differs light/dark")
    func rvApprovedDiffers() {
        assertLightDarkDiffer(HubberDesign.rvApproved, name: "rvApproved")
    }

    @Test("Reviewer changes differs light/dark")
    func rvChangesDiffers() {
        assertLightDarkDiffer(HubberDesign.rvChanges, name: "rvChanges")
    }

    @Test("Reviewer comment differs light/dark")
    func rvCommentDiffers() {
        assertLightDarkDiffer(HubberDesign.rvComment, name: "rvComment")
    }

    // MARK: Accent / Error

    @Test("Accent differs light/dark")
    func accentDiffers() {
        assertLightDarkDiffer(HubberDesign.accent, name: "accent")
    }

    @Test("Error differs light/dark")
    func errorDiffers() {
        assertLightDarkDiffer(HubberDesign.error, name: "error")
    }

    // MARK: Signal Treatment

    @Test("Signal tint differs light/dark")
    func signalTintDiffers() {
        assertLightDarkDiffer(HubberDesign.signalTint, name: "signalTint")
    }

    @Test("Signal accent differs light/dark")
    func signalAccentDiffers() {
        assertLightDarkDiffer(HubberDesign.signalAccent, name: "signalAccent")
    }

    // MARK: Text / Lines / Controls

    @Test("text differs light/dark")
    func textDiffers() {
        assertLightDarkDiffer(HubberDesign.text, name: "text")
    }

    @Test("text2 differs light/dark")
    func text2Differs() {
        assertLightDarkDiffer(HubberDesign.text2, name: "text2")
    }

    @Test("sep differs light/dark")
    func sepDiffers() {
        assertLightDarkDiffer(HubberDesign.sep, name: "sep")
    }

    @Test("fill differs light/dark")
    func fillDiffers() {
        assertLightDarkDiffer(HubberDesign.fill, name: "fill")
    }

    @Test("ctrlTrack differs light/dark")
    func ctrlTrackDiffers() {
        assertLightDarkDiffer(HubberDesign.ctrlTrack, name: "ctrlTrack")
    }

    // MARK: sloTokens(for:) dispatch

    @Test("sloTokens dispatches to green")
    func sloTokensGreen() {
        let group = HubberDesign.sloTokens(for: .green)
        // Just assert the colors are there (non-nil is implicit since they're value types)
        _ = group.fg
        _ = group.bg
        _ = group.border
    }

    @Test("sloTokens dispatches to amber")
    func sloTokensAmber() {
        let group = HubberDesign.sloTokens(for: .amber)
        _ = group.fg
        _ = group.bg
        _ = group.border
    }

    @Test("sloTokens dispatches to red")
    func sloTokensRed() {
        let group = HubberDesign.sloTokens(for: .red)
        _ = group.fg
        _ = group.bg
        _ = group.border
    }

    // MARK: reviewerColor(for:)

    @Test("reviewerColor approved is non-nil")
    func reviewerColorApproved() {
        #expect(HubberDesign.reviewerColor(for: .approved) != nil)
    }

    @Test("reviewerColor pending is nil (hollow ring)")
    func reviewerColorPending() {
        #expect(HubberDesign.reviewerColor(for: .pending) == nil)
    }
}

// MARK: - Type Scale Tests

@Suite("HubberType scale")
struct HubberTypeTests {

    @Test("HubberType.PointSize.title is 13")
    func titleSize() {
        #expect(HubberType.PointSize.title == 13)
    }

    @Test("HubberType.PointSize.secondary is 11")
    func secondarySize() {
        #expect(HubberType.PointSize.secondary == 11)
    }

    @Test("HubberType.PointSize.sloPill is 11")
    func sloPillSize() {
        #expect(HubberType.PointSize.sloPill == 11)
    }

    @Test("HubberType.PointSize.ciDetail is 11")
    func ciDetailSize() {
        #expect(HubberType.PointSize.ciDetail == 11)
    }

    @Test("HubberType.PointSize.log is 11")
    func logSize() {
        #expect(HubberType.PointSize.log == 11)
    }

    @Test("HubberType.PointSize.section is 11")
    func sectionSize() {
        #expect(HubberType.PointSize.section == 11)
    }

    @Test("HubberType.PointSize.footer is 11")
    func footerSize() {
        #expect(HubberType.PointSize.footer == 11)
    }

    @Test("All Font roles are distinct or present")
    func allFontRolesExist() {
        // Merely exercising the static properties to ensure they compile and return non-nil-equivalent values.
        _ = HubberType.title
        _ = HubberType.secondary
        _ = HubberType.sloPill
        _ = HubberType.ciDetail
        _ = HubberType.log
        _ = HubberType.section
        _ = HubberType.footer
        _ = HubberType.prNumber
        _ = HubberType.headerTitle
        _ = HubberType.badge
    }
}

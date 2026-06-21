import AppKit
import SwiftUI
import Testing
@testable import Hubber

@Suite("Contrast ratio math")
struct ContrastRatioMathTests {
    @Test("black on white is 21:1")
    func blackWhite() {
        let r = ContrastRatio.ratio(.black, .white)
        #expect(abs(r - 21.0) < 0.1)
    }

    @Test("identical colors are 1:1")
    func identical() {
        let r = ContrastRatio.ratio(.white, .white)
        #expect(abs(r - 1.0) < 0.01)
    }

    @Test("compositing 50% black over white yields mid-gray")
    func composite() throws {
        let half = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5)
        let out = try #require(ContrastRatio.composite(half, over: .white).usingColorSpace(.sRGB))
        #expect(abs(out.redComponent - 0.5) < 0.02)
    }
}

@Suite("Token contrast meets WCAG AA")
struct ContrastTests {
    /// Resolve a SwiftUI Color to its sRGB NSColor in a specific appearance.
    private func resolve(_ color: Color, _ appearance: NSAppearance) -> NSColor {
        var out = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB) ?? .black
        }
        return out
    }

    private struct Pair {
        let name: String
        let fg: Color
        let bg: Color // opaque or translucent; composited over base
        let min: Double // 4.5 text, 3.0 UI/large
    }

    /// Representative opaque base each surface sits on (popover material).
    private func base(_ appearance: NSAppearance) -> NSColor {
        resolve(HubberDesign.materialSolid, appearance)
    }

    private func pairs() -> [Pair] {
        [
            Pair(name: "text on base", fg: HubberDesign.text, bg: HubberDesign.materialSolid, min: 4.5),
            Pair(name: "text2 on base", fg: HubberDesign.text2, bg: HubberDesign.materialSolid, min: 4.5),
            Pair(name: "SLO green fg on its bg", fg: HubberDesign.sloGreen.fg, bg: HubberDesign.sloGreen.bg, min: 4.5),
            Pair(name: "SLO amber fg on its bg", fg: HubberDesign.sloAmber.fg, bg: HubberDesign.sloAmber.bg, min: 4.5),
            Pair(name: "SLO red fg on its bg", fg: HubberDesign.sloRed.fg, bg: HubberDesign.sloRed.bg, min: 4.5),
            Pair(name: "CI passing on base", fg: HubberDesign.ciPassing, bg: HubberDesign.materialSolid, min: 3.0),
            Pair(name: "CI failing on base", fg: HubberDesign.ciFailing, bg: HubberDesign.materialSolid, min: 3.0),
            Pair(name: "accent on base", fg: HubberDesign.accent, bg: HubberDesign.materialSolid, min: 3.0),
        ]
    }

    @Test("all token pairs meet AA in light and dark")
    func tokenPairs() {
        guard let light = NSAppearance(named: .aqua), let dark = NSAppearance(named: .darkAqua) else {
            Issue.record("appearances unavailable")
            return
        }
        for appearance in [light, dark] {
            let label = appearance.name == .darkAqua ? "dark" : "light"
            for p in pairs() {
                let bg = ContrastRatio.composite(resolve(p.bg, appearance), over: base(appearance))
                let fg = ContrastRatio.composite(resolve(p.fg, appearance), over: bg)
                let r = ContrastRatio.ratio(fg, bg)
                #expect(r >= p.min, "\(p.name) [\(label)] = \(String(format: "%.2f", r)):1, need \(p.min):1")
            }
        }
    }
}

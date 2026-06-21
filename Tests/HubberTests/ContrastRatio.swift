import AppKit

/// WCAG 2.1 relative-luminance + contrast-ratio math, plus alpha compositing.
/// Lives in the test target — it exists to gate design tokens, not ship in the app.
enum ContrastRatio {
    /// Composite a (possibly translucent) foreground over an opaque background.
    static func composite(_ fg: NSColor, over bg: NSColor) -> NSColor {
        guard let f = fg.usingColorSpace(.sRGB), let b = bg.usingColorSpace(.sRGB) else { return fg }
        let a = f.alphaComponent
        return NSColor(
            srgbRed: f.redComponent * a + b.redComponent * (1 - a),
            green: f.greenComponent * a + b.greenComponent * (1 - a),
            blue: f.blueComponent * a + b.blueComponent * (1 - a),
            alpha: 1
        )
    }

    private static func linearize(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// WCAG relative luminance of an opaque color.
    static func luminance(_ color: NSColor) -> Double {
        guard let c = color.usingColorSpace(.sRGB) else { return 0 }
        return 0.2126 * linearize(c.redComponent)
            + 0.7152 * linearize(c.greenComponent)
            + 0.0722 * linearize(c.blueComponent)
    }

    /// Contrast ratio between two opaque colors (composite translucent ones first).
    static func ratio(_ a: NSColor, _ b: NSColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }
}

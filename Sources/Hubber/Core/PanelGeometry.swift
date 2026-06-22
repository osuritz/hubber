import Foundation

/// Pure height math for the menu-bar panel. Contains no AppKit types so it can be
/// unit-tested without a display.
///
/// Width is a discrete user preset (see `PanelWidth`). Height adapts to the host screen:
/// ~60% of the usable height, floored so laptops never shrink below today's size, and
/// capped to the space below the menu bar so the panel never runs off the bottom.
enum PanelGeometry {

    // MARK: - Height (screen-adaptive)

    /// Fraction of the screen's usable height the panel aims to fill.
    static let heightFraction = 0.60

    /// Floor so laptops never get a panel shorter than today's fixed 540pt.
    static let minHeight = 540.0

    /// Computes the panel height for the screen hosting the menu-bar item.
    ///
    /// All values are AppKit screen coordinates (origin bottom-left), so the menu-bar
    /// button's `buttonMinY` is near the TOP of the screen and the panel hangs below it.
    ///
    /// - Parameters:
    ///   - screenVisibleHeight: `visibleFrame.height` of the host screen.
    ///   - screenVisibleMinY: `visibleFrame.minY` of the host screen (the usable bottom edge).
    ///   - buttonMinY: the menu-bar button's bottom edge in screen coordinates.
    ///   - gap: vertical gap between the button and the panel's top edge.
    /// - Returns: a height that is ~`heightFraction` of the usable height, never below
    ///   `minHeight` unless the available space forces it, and never taller than the space
    ///   between the menu bar and the bottom of the screen.
    static func height(
        screenVisibleHeight: Double,
        screenVisibleMinY: Double,
        buttonMinY: Double,
        gap: Double,
        fraction: Double = heightFraction,
        minHeight: Double = minHeight
    ) -> Double {
        let target = fraction * screenVisibleHeight
        let maxFit = buttonMinY - gap - screenVisibleMinY
        return min(max(target, minHeight), maxFit)
    }
}

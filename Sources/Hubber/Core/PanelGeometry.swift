import Foundation

/// Pure placement math for the menu-bar panel. Contains no AppKit types so it can be
/// unit-tested without a display.
///
/// Width is a discrete user preset (see `PanelWidth`). Height adapts to the host screen:
/// ~60% of the usable height, floored so laptops never shrink below today's size, and
/// capped to the space below the menu bar so the panel never runs off the bottom. The
/// horizontal origin hangs the panel under the status item but keeps a small inset from the
/// screen edges so it never hugs them (matching Control Center / Notification Center).
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
        // Degenerate geometry (e.g. a bogus/zero button frame) can make maxFit ≤ 0. Never
        // return a non-positive height — fall back to the floor so the panel frame stays valid.
        guard maxFit > 0 else { return minHeight }
        return min(max(target, minHeight), maxFit)
    }

    // MARK: - Horizontal placement

    /// Minimum inset the panel keeps from the left/right edges of the screen's usable area, so a
    /// wide panel (or a status item near the edge) never hugs the screen edge.
    static let screenEdgeMargin = 8.0

    /// Computes the panel's left (x) origin in AppKit screen coordinates.
    ///
    /// The panel hangs under the status item — left-aligned to the button when it fits, otherwise
    /// right-aligned to it — then clamped so it stays within the usable frame inset by
    /// `edgeMargin` on both sides. The clamp only changes placement when the button is close
    /// enough to an edge that the panel would otherwise spill into the margin.
    static func originX(
        buttonMinX: Double,
        buttonMaxX: Double,
        width: Double,
        visibleMinX: Double,
        visibleMaxX: Double,
        edgeMargin: Double = screenEdgeMargin
    ) -> Double {
        let preferredLeftAligned = buttonMinX
        let preferredRightAligned = buttonMaxX - width
        let unclamped = preferredLeftAligned + width <= visibleMaxX
            ? preferredLeftAligned
            : preferredRightAligned
        let lowerBound = visibleMinX + edgeMargin
        let upperBound = visibleMaxX - width - edgeMargin
        return min(max(unclamped, lowerBound), upperBound)
    }
}

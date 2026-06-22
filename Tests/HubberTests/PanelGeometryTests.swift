import Foundation
import XCTest
@testable import Hubber

// MARK: - PanelGeometryTests

//
// Pure geometry for the menu-bar panel: width is a discrete preset (PanelWidth) and the
// height adapts to the host screen (~60% of the usable height, floored so laptops never
// shrink, and capped to the space below the menu bar so it never runs off-screen).
//
// Screen coordinates are AppKit's (origin bottom-left): the menu-bar button's `minY` sits
// near the TOP of the screen (a large value), and the panel hangs below it.

final class PanelGeometryTests: XCTestCase {

    // MARK: - Height

    /// Typical 14" laptop: 60% of ~930pt usable height ≈ 558, above the 540 floor and well
    /// within the space below the menu bar.
    func testHeightOnLaptopUsesFraction() {
        let h = PanelGeometry.height(
            screenVisibleHeight: 930,
            screenVisibleMinY: 0,
            buttonMinY: 930,
            gap: 6
        )
        XCTAssertEqual(h, 558, accuracy: 0.5)
    }

    /// Small laptop: 60% of ~775 ≈ 465, raised to the 540 floor (there is room for it).
    func testHeightOnSmallScreenIsFlooredTo540() {
        let h = PanelGeometry.height(
            screenVisibleHeight: 775,
            screenVisibleMinY: 0,
            buttonMinY: 775,
            gap: 6
        )
        XCTAssertEqual(h, 540, accuracy: 0.5)
    }

    /// Large external display: 60% of ~1415 ≈ 849 — more rows on screen at once.
    func testHeightOnLargeExternalGrows() {
        let h = PanelGeometry.height(
            screenVisibleHeight: 1415,
            screenVisibleMinY: 0,
            buttonMinY: 1415,
            gap: 6
        )
        XCTAssertEqual(h, 849, accuracy: 0.5)
    }

    /// Shallow usable area: the on-screen fit (maxFit) must win even when it forces the
    /// panel below the 540 floor, so the panel never runs off the bottom of the screen.
    func testHeightClampedToFitWhenFloorWouldOverflow() {
        // buttonMinY 475, gap 6, visibleMinY 0 → maxFit = 469 (< 540 floor)
        let h = PanelGeometry.height(
            screenVisibleHeight: 475,
            screenVisibleMinY: 0,
            buttonMinY: 475,
            gap: 6
        )
        XCTAssertEqual(h, 469, accuracy: 0.5)
    }

    /// Degenerate geometry (button at/below the usable bottom → maxFit ≤ 0) must never yield a
    /// zero/negative height; fall back to the floor so an invalid frame is never constructed.
    func testHeightFallsBackToFloorWhenGeometryIsDegenerate() {
        // buttonMinY 100, gap 6, visibleMinY 100 → maxFit = -6 (≤ 0)
        let h = PanelGeometry.height(
            screenVisibleHeight: 900,
            screenVisibleMinY: 100,
            buttonMinY: 100,
            gap: 6
        )
        XCTAssertEqual(h, PanelGeometry.minHeight, accuracy: 0.5)
    }

    // MARK: - Horizontal placement (originX)

    /// When the status item sits near the screen's right edge, the panel must not hug the edge —
    /// its right edge keeps a `screenEdgeMargin` inset (like Control Center / Notification Center).
    func testOriginXLeavesMarginWhenButtonNearRightEdge() {
        let x = PanelGeometry.originX(
            buttonMinX: 1400,
            buttonMaxX: 1440,
            width: 520,
            visibleMinX: 0,
            visibleMaxX: 1440
        )
        // right edge = x + width should be margin away from the screen's right edge
        XCTAssertEqual(x + 520, 1440 - PanelGeometry.screenEdgeMargin, accuracy: 0.5)
    }

    /// When the status item is away from the edge, the panel still anchors its right edge to the
    /// button (no margin clamp needed) — placement is unchanged for the common case.
    func testOriginXAnchorsToButtonWhenAwayFromEdge() {
        let x = PanelGeometry.originX(
            buttonMinX: 960,
            buttonMaxX: 1000,
            width: 520,
            visibleMinX: 0,
            visibleMaxX: 1440
        )
        XCTAssertEqual(x + 520, 1000, accuracy: 0.5) // right edge at the button, not the screen edge
    }

    /// The margin is measured against the *host screen's* usable frame, not absolute zero —
    /// verifies a right-edge button on a secondary display to the right of the main one.
    func testOriginXMarginIsRelativeToHostScreen() {
        let x = PanelGeometry.originX(
            buttonMinX: 2840,
            buttonMaxX: 2880,
            width: 520,
            visibleMinX: 1440,
            visibleMaxX: 2880
        )
        XCTAssertEqual(x + 520, 2880 - PanelGeometry.screenEdgeMargin, accuracy: 0.5)
    }
}

// MARK: - PanelWidthTests

final class PanelWidthTests: XCTestCase {
    func testPointsMapping() {
        XCTAssertEqual(PanelWidth.narrow.points, 400)
        XCTAssertEqual(PanelWidth.normal.points, 460)
        XCTAssertEqual(PanelWidth.wide.points, 520)
    }

    func testRawValuesAreStable() {
        XCTAssertEqual(PanelWidth.narrow.rawValue, 1)
        XCTAssertEqual(PanelWidth.normal.rawValue, 2)
        XCTAssertEqual(PanelWidth.wide.rawValue, 3)
    }

    func testTitles() {
        XCTAssertEqual(PanelWidth.narrow.title, "Narrow")
        XCTAssertEqual(PanelWidth.normal.title, "Normal")
        XCTAssertEqual(PanelWidth.wide.title, "Wide")
    }
}

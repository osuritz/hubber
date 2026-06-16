import Foundation
import XCTest
@testable import Hubber

final class MenubarPresentationTests: XCTestCase {

    // MARK: - badgeCount

    func testOffModeAlwaysReturnsNil() {
        XCTAssertNil(MenubarPresentation.badgeCount(mode: .off, incomingCount: 0, attentionCount: 0))
        XCTAssertNil(MenubarPresentation.badgeCount(mode: .off, incomingCount: 5, attentionCount: 3))
    }

    func testIncomingCountModeReturnsCountWhenPositive() {
        XCTAssertEqual(MenubarPresentation.badgeCount(mode: .incomingCount, incomingCount: 3, attentionCount: 0), 3)
    }

    func testIncomingCountModeReturnsNilWhenZero() {
        XCTAssertNil(MenubarPresentation.badgeCount(mode: .incomingCount, incomingCount: 0, attentionCount: 5))
    }

    func testAttentionNeededModeReturnsAttentionCountWhenPositive() {
        XCTAssertEqual(MenubarPresentation.badgeCount(mode: .attentionNeeded, incomingCount: 0, attentionCount: 4), 4)
    }

    func testAttentionNeededModeReturnsNilWhenZero() {
        XCTAssertNil(MenubarPresentation.badgeCount(mode: .attentionNeeded, incomingCount: 7, attentionCount: 0))
    }

    func testAttentionNeededModeIgnoresIncomingCount() {
        XCTAssertEqual(
            MenubarPresentation.badgeCount(mode: .attentionNeeded, incomingCount: 10, attentionCount: 2),
            2
        )
    }

    func testIncomingCountModeIgnoresAttentionCount() {
        XCTAssertEqual(
            MenubarPresentation.badgeCount(mode: .incomingCount, incomingCount: 7, attentionCount: 99),
            7
        )
    }

    // MARK: - state

    func testStateWithNilBadgeCountAndNotRefreshing() {
        let s = MenubarPresentation.state(badgeCount: nil, isRefreshing: false)
        XCTAssertNil(s.badgeText)
        XCTAssertFalse(s.isRefreshing)
    }

    func testStateWithBadgeCountMapsToBadgeText() {
        let s = MenubarPresentation.state(badgeCount: 7, isRefreshing: false)
        XCTAssertEqual(s.badgeText, "7")
        XCTAssertFalse(s.isRefreshing)
    }

    func testStatePassesThroughIsRefreshing() {
        let s = MenubarPresentation.state(badgeCount: nil, isRefreshing: true)
        XCTAssertNil(s.badgeText)
        XCTAssertTrue(s.isRefreshing)
    }

    // MARK: - state — live combined case (B)

    func testStateRefreshingWhileAttentionBadgeShown() {
        // badgeCount: 5 attention items while a refresh is in progress
        let s = MenubarPresentation.state(badgeCount: 5, isRefreshing: true)
        XCTAssertEqual(s.badgeText, "5")
        XCTAssertTrue(s.isRefreshing)
    }

    // MARK: - state — Equatable via factory (C)

    func testStateEqualWhenFactoryInputsMatch() {
        // Two state(...) calls with identical inputs must produce equal States,
        // exercising both the factory and the synthesised Equatable conformance.
        let a = MenubarPresentation.state(badgeCount: 3, isRefreshing: false)
        let b = MenubarPresentation.state(badgeCount: 3, isRefreshing: false)
        XCTAssertEqual(a, b)
        let c = MenubarPresentation.state(badgeCount: nil, isRefreshing: true)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - tooltip (A)

    func testTooltipAttentionNeededWhenZero() {
        XCTAssertEqual(
            MenubarPresentation.tooltip(mode: .attentionNeeded, incomingCount: 0, attentionCount: 0),
            "Hubber — nothing needs attention"
        )
    }

    func testTooltipAttentionNeededWhenPositive() {
        XCTAssertEqual(
            MenubarPresentation.tooltip(mode: .attentionNeeded, incomingCount: 0, attentionCount: 3),
            "Hubber — 3 item(s) need attention"
        )
    }

    func testTooltipIncomingCountMode() {
        XCTAssertEqual(
            MenubarPresentation.tooltip(mode: .incomingCount, incomingCount: 5, attentionCount: 2),
            "Hubber — 5 incoming review(s)"
        )
    }

    func testTooltipIncomingCountModeWhenZero() {
        XCTAssertEqual(
            MenubarPresentation.tooltip(mode: .incomingCount, incomingCount: 0, attentionCount: 0),
            "Hubber — 0 incoming review(s)"
        )
    }

    func testTooltipOffMode() {
        XCTAssertEqual(
            MenubarPresentation.tooltip(mode: .off, incomingCount: 7, attentionCount: 2),
            "Hubber — badge off (2 need attention)"
        )
    }

    func testTooltipOffModeWhenZeroAttention() {
        XCTAssertEqual(
            MenubarPresentation.tooltip(mode: .off, incomingCount: 0, attentionCount: 0),
            "Hubber — badge off (0 need attention)"
        )
    }

    // MARK: - accessibilityValue (A)

    func testAccessibilityValueOffModeIsNil() {
        XCTAssertNil(MenubarPresentation.accessibilityValue(mode: .off, incomingCount: 0, attentionCount: 0))
        XCTAssertNil(MenubarPresentation.accessibilityValue(mode: .off, incomingCount: 5, attentionCount: 3))
    }

    func testAccessibilityValueIncomingCountWhenPositive() {
        XCTAssertEqual(
            MenubarPresentation.accessibilityValue(mode: .incomingCount, incomingCount: 4, attentionCount: 0),
            "4"
        )
    }

    func testAccessibilityValueIncomingCountWhenZeroIsNil() {
        XCTAssertNil(
            MenubarPresentation.accessibilityValue(mode: .incomingCount, incomingCount: 0, attentionCount: 5)
        )
    }

    func testAccessibilityValueAttentionNeededWhenPositive() {
        XCTAssertEqual(
            MenubarPresentation.accessibilityValue(mode: .attentionNeeded, incomingCount: 0, attentionCount: 2),
            "2"
        )
    }

    func testAccessibilityValueAttentionNeededWhenZeroIsNil() {
        XCTAssertNil(
            MenubarPresentation.accessibilityValue(mode: .attentionNeeded, incomingCount: 7, attentionCount: 0)
        )
    }
}

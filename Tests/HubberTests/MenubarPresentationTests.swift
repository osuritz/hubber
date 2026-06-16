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

    func testStateEquatable() {
        let a = MenubarPresentation.State(badgeText: "3", isRefreshing: false)
        let b = MenubarPresentation.State(badgeText: "3", isRefreshing: false)
        let c = MenubarPresentation.State(badgeText: nil, isRefreshing: true)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

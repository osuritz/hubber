import XCTest
@testable import Hubber

final class TimeFormattingTests: XCTestCase {
    func testRemainingCompactUsesMinutesThroughNinetyOneMinutes() {
        XCTAssertEqual(remainingText(hours: 72.0 / 60.0), "72m left")
        XCTAssertEqual(remainingText(hours: 90.0 / 60.0), "90m left")
        XCTAssertEqual(remainingText(hours: 91.0 / 60.0), "91m left")
    }

    func testRemainingCompactRoundsToNearestHalfHourAfterNinetyOneMinutes() {
        XCTAssertEqual(remainingText(hours: 92.0 / 60.0), "1 ½ h left")
        XCTAssertEqual(remainingText(hours: 149.0 / 60.0), "2 ½ h left")
        XCTAssertEqual(remainingText(hours: 151.0 / 60.0), "2 ½ h left")
    }

    func testOverCompactUsesMinutesThroughNinetyOneMinutes() {
        XCTAssertEqual(remainingText(hours: -72.0 / 60.0), "72m over")
        XCTAssertEqual(remainingText(hours: -90.0 / 60.0), "90m over")
        XCTAssertEqual(remainingText(hours: -91.0 / 60.0), "91m over")
    }

    func testOverCompactRoundsToNearestHalfHourAfterNinetyOneMinutes() {
        XCTAssertEqual(remainingText(hours: -92.0 / 60.0), "1 ½ h over")
        XCTAssertEqual(remainingText(hours: -149.0 / 60.0), "2 ½ h over")
        XCTAssertEqual(remainingText(hours: -151.0 / 60.0), "2 ½ h over")
    }

    func testRemainingDetailKeepsFullHoursAndMinutesForHoverText() {
        XCTAssertEqual(remainingDetailText(hours: 92.0 / 60.0), "1 h 32m left")
        XCTAssertEqual(remainingDetailText(hours: -92.0 / 60.0), "1 h 32m over")
    }
}

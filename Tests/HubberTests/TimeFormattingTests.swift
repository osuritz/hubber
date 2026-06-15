import XCTest
@testable import Hubber

final class TimeFormattingTests: XCTestCase {
    func testElapsedTextFormatsShortDurations() {
        XCTAssertEqual(elapsedText(hours: 0.5 / 60.0), "just now")
        XCTAssertEqual(elapsedText(hours: 45.0 / 60.0), "45m ago")
        XCTAssertEqual(elapsedText(hours: 2.5), "2 h 30m ago")
    }

    func testElapsedTextRoundsToNearestHalfDayAfterTwentyFourHours() {
        XCTAssertEqual(elapsedText(hours: 24), "1 d ago")
        XCTAssertEqual(elapsedText(hours: 30), "1 ½ d ago")
        XCTAssertEqual(elapsedText(hours: 42), "2 d ago")
    }

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

    func testRemainingCompactRoundsToNearestHalfDayAfterTwentyFourHours() {
        XCTAssertEqual(remainingText(hours: 24), "1 d left")
        XCTAssertEqual(remainingText(hours: 30), "1 ½ d left")
        XCTAssertEqual(remainingText(hours: 42), "2 d left")
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

    func testOverCompactRoundsToNearestHalfDayAfterTwentyFourHours() {
        XCTAssertEqual(remainingText(hours: -24), "1 d over")
        XCTAssertEqual(remainingText(hours: -30), "1 ½ d over")
        XCTAssertEqual(remainingText(hours: -42), "2 d over")
    }

    func testRemainingDetailKeepsFullHoursAndMinutesForHoverText() {
        XCTAssertEqual(remainingDetailText(hours: 92.0 / 60.0), "1 h 32m left")
        XCTAssertEqual(remainingDetailText(hours: -92.0 / 60.0), "1 h 32m over")
    }

}

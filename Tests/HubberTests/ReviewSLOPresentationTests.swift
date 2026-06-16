import XCTest
@testable import Hubber

final class ReviewSLOPresentationTests: XCTestCase {
    func testFooterTextReflectsSLOVisibility() {
        XCTAssertEqual(ReviewSLOPresentation.footerText(isEnabled: true, hours: 4), "SLO 4h")
        XCTAssertEqual(ReviewSLOPresentation.footerText(isEnabled: false, hours: 4), "SLO off")
    }

    func testRateLimitFooterFormatsMinutes() {
        XCTAssertEqual(
            ReviewSLOPresentation.rateLimitFooter(secondsRemaining: 900),
            "Rate limited — next refresh in 15m"
        )
        XCTAssertEqual(
            ReviewSLOPresentation.rateLimitFooter(secondsRemaining: 60),
            "Rate limited — next refresh in 1m"
        )
        XCTAssertEqual(
            ReviewSLOPresentation.rateLimitFooter(secondsRemaining: 30),
            "Rate limited — next refresh in 1m"
        )
        XCTAssertEqual(
            ReviewSLOPresentation.rateLimitFooter(secondsRemaining: 120),
            "Rate limited — next refresh in 2m"
        )
    }
}

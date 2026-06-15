import XCTest
@testable import Hubber

final class ReviewSLOPresentationTests: XCTestCase {
    func testSettingsCopyMatchesReviewSLOLayout() {
        XCTAssertEqual(ReviewSLOPresentation.settingsSectionTitle, "Incoming Reviews")
        XCTAssertEqual(ReviewSLOPresentation.title, "Review SLO")
        XCTAssertEqual(ReviewSLOPresentation.subtitle, "Show timing badges for incoming review requests.")
        XCTAssertEqual(ReviewSLOPresentation.windowLabel, "Review window")
        XCTAssertEqual(
            ReviewSLOPresentation.thresholdHelp,
            "Reviews are flagged amber at 50% and red at 100% of this budget."
        )
    }

    func testFooterTextReflectsSLOVisibility() {
        XCTAssertEqual(ReviewSLOPresentation.footerText(isEnabled: true, hours: 4), "SLO 4h")
        XCTAssertEqual(ReviewSLOPresentation.footerText(isEnabled: false, hours: 4), "SLO off")
    }
}

import XCTest
@testable import Hubber

final class ReviewSLOPresentationTests: XCTestCase {
    func testFooterTextReflectsSLOVisibility() {
        XCTAssertEqual(ReviewSLOPresentation.footerText(isEnabled: true, hours: 4), "SLO 4h")
        XCTAssertEqual(ReviewSLOPresentation.footerText(isEnabled: false, hours: 4), "SLO off")
    }
}

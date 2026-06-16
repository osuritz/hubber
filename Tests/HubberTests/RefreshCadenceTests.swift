import XCTest
@testable import Hubber

final class RefreshCadenceTests: XCTestCase {

    // MARK: - Individual row tests

    func testRateLimitedReturns900() {
        let ctx = RefreshContext(isRateLimited: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 15 * 60)
    }

    func testUrgentSLOReturns30() {
        let ctx = RefreshContext(hasUrgentSLO: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 30)
    }

    func testPopoverOpenReturns60() {
        let ctx = RefreshContext(isPopoverOpen: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 60)
    }

    func testIdleAndAllGreenReturns900() {
        let ctx = RefreshContext(isMachineIdle: true, isAllGreen: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 15 * 60)
    }

    func testBackgroundNormalReturns300() {
        let ctx = RefreshContext()
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 5 * 60)
    }

    // MARK: - Precedence tests

    func testRateLimitedOverridesUrgentSLO() {
        let ctx = RefreshContext(isRateLimited: true, hasUrgentSLO: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 15 * 60)
    }

    func testRateLimitedOverridesPopoverOpen() {
        let ctx = RefreshContext(isRateLimited: true, isPopoverOpen: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 15 * 60)
    }

    func testUrgentSLOBeatsPopoverOpen() {
        let ctx = RefreshContext(hasUrgentSLO: true, isPopoverOpen: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 30)
    }

    func testPopoverOpenBeatsBackground() {
        let ctx = RefreshContext(isPopoverOpen: true, isMachineIdle: false, isAllGreen: false)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 60)
    }

    func testIdleButNotAllGreenReturnsBackground() {
        let ctx = RefreshContext(isMachineIdle: true, isAllGreen: false)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 5 * 60)
    }

    func testAllGreenButNotIdleReturnsBackground() {
        let ctx = RefreshContext(isMachineIdle: false, isAllGreen: true)
        XCTAssertEqual(RefreshCadence.interval(for: ctx), 5 * 60)
    }
}

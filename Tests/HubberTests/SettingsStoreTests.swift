import Foundation
import XCTest
@testable import Hubber

@MainActor
final class SettingsStoreTests: XCTestCase {
    private var sut: SettingsStore!
    private var defaults: UserDefaults!
    private nonisolated(unsafe) var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "SettingsStoreTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        sut = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultSLOHoursIs4() {
        XCTAssertEqual(sut.sloHours, 4.0)
    }

    func testDefaultSLOEnabledIsTrue() {
        XCTAssertTrue(sut.sloEnabled)
    }

    func testDefaultIncomingModeIsExplicit() {
        XCTAssertEqual(sut.incomingMode, .explicit)
    }

    func testDefaultUnresolvedModeIsAllOpen() {
        XCTAssertEqual(sut.unresolvedMode, .allOpen)
    }

    func testDefaultRowDensityIsNormal() {
        XCTAssertEqual(sut.rowDensity, .normal)
    }

    func testSloHoursPersistedToUserDefaults() {
        sut.sloHours = 8.0
        XCTAssertEqual(defaults.double(forKey: "sloWindowHours"), 8.0)
    }

    func testIncomingModePersistedToUserDefaults() {
        sut.incomingMode = .team
        XCTAssertEqual(defaults.string(forKey: "incomingMode"), IncomingReviewMode.team.rawValue)
    }

    func testSloHoursForRepoReturnsGlobalValue() {
        sut.sloHours = 6.0
        XCTAssertEqual(sut.sloHours(for: "acme/payments-api"), 6.0)
        XCTAssertEqual(sut.sloHours(for: "acme/web"), 6.0)
    }

    func testUserDefaultsValueOverridesHardcodedDefault() {
        defaults.set(12.0, forKey: "sloWindowHours")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.sloHours, 12.0)
    }
}

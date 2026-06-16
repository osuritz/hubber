import Foundation
import XCTest
@testable import Hubber

// MARK: - ManagedPreferencesTests
//
// Uses InMemoryManagedPreferences (the test fake) to verify the protocol contract:
//   • isForced returns true iff the key is present in the fake's dictionary.
//   • value(_:) returns the stored value when present, nil otherwise.
//   • Typed helpers cover Bool, Int, Double, String, and [String].
//
// CFManagedPreferences itself is not tested here — it delegates to CFPreferences which
// cannot be forced in a bundle-less xctest host. The protocol contract + fake tests
// give us sufficient coverage for everything that calls through the seam.

@MainActor
final class ManagedPreferencesTests: XCTestCase {

    // MARK: - isForced

    func testIsForcedTrueWhenKeyPresent() {
        let prefs = InMemoryManagedPreferences(["sloEnabled": true])
        XCTAssertTrue(prefs.isForced("sloEnabled"))
    }

    func testIsForcedFalseWhenKeyAbsent() {
        let prefs = InMemoryManagedPreferences([:])
        XCTAssertFalse(prefs.isForced("sloEnabled"))
    }

    // MARK: - value(_:)

    func testValueReturnsBoolWhenPresent() {
        let prefs = InMemoryManagedPreferences(["sloEnabled": false])
        XCTAssertEqual(prefs.value("sloEnabled") as? Bool, false)
    }

    func testValueReturnsIntWhenPresent() {
        let prefs = InMemoryManagedPreferences(["sloWindowHours": 8])
        XCTAssertEqual(prefs.value("sloWindowHours") as? Int, 8)
    }

    func testValueReturnsDoubleWhenPresent() {
        let prefs = InMemoryManagedPreferences(["sloWindowHours": 8.5])
        XCTAssertEqual(prefs.value("sloWindowHours") as? Double, 8.5)
    }

    func testValueReturnsStringWhenPresent() {
        let prefs = InMemoryManagedPreferences(["sloDisplay": "remaining"])
        XCTAssertEqual(prefs.value("sloDisplay") as? String, "remaining")
    }

    func testValueReturnsStringArrayWhenPresent() {
        let prefs = InMemoryManagedPreferences(["defaultNotificationEvents": ["newReview", "ciFailed"]])
        XCTAssertEqual(prefs.value("defaultNotificationEvents") as? [String], ["newReview", "ciFailed"])
    }

    func testValueReturnsNilWhenAbsent() {
        let prefs = InMemoryManagedPreferences([:])
        XCTAssertNil(prefs.value("sloEnabled"))
    }

    // MARK: - ManagedKey registry coverage
    //
    // Verifies that every PRD-defined managed key constant is present and non-empty.
    // This acts as a regression guard against accidental key renames.

    func testManagedKeyRegistryCoversAllPRDKeys() {
        let allKeys: [String] = [
            ManagedKey.sloEnabled,
            ManagedKey.sloWindowHours,
            ManagedKey.sloDisplay,
            ManagedKey.badgeMode,
            ManagedKey.incomingMode,
            ManagedKey.unresolvedThreadMode,
            ManagedKey.rowDensity,
            ManagedKey.analyticsEnabled,
            ManagedKey.crashReportingEnabled,
            ManagedKey.notificationsEnabled,
            ManagedKey.defaultNotificationEvents,
            ManagedKey.providerAllowlist,
            ManagedKey.allowPersonalGitHub,
        ]
        // All keys must be non-empty strings.
        for key in allKeys {
            XCTAssertFalse(key.isEmpty, "ManagedKey constant must not be empty")
        }
        // All keys must be unique.
        XCTAssertEqual(allKeys.count, Set(allKeys).count, "ManagedKey constants must be unique")
    }

    // MARK: - Sendable conformance

    func testInMemoryManagedPreferencesIsSendable() {
        // Compile-time check: InMemoryManagedPreferences must conform to Sendable
        // so it can be captured across concurrency boundaries.
        let prefs: any ManagedPreferences = InMemoryManagedPreferences(["k": "v"])
        XCTAssertTrue(prefs.isForced("k"))
    }
}

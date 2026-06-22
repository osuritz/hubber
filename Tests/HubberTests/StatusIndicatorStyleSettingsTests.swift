import Foundation
import XCTest
@testable import Hubber

/// Persistence + MDM resolution for the `statusIndicatorStyle` setting (rail vs badge).
/// Mirrors the `rowDensity` coverage in SettingsStoreTests; kept in its own file so neither
/// type body exceeds the lint length limit.
@MainActor
final class StatusIndicatorStyleSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "StatusIndicatorStyleSettingsTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeStore(managed: InMemoryManagedPreferences = InMemoryManagedPreferences()) -> SettingsStore {
        SettingsStore(defaults: defaults, managed: managed)
    }

    func testDefaultIsRail() {
        XCTAssertEqual(makeStore().statusIndicatorStyle, .rail)
    }

    func testPersistedToUserDefaults() {
        let store = makeStore()
        store.statusIndicatorStyle = .badge
        XCTAssertEqual(defaults.string(forKey: "statusIndicatorStyle"), StatusIndicatorStyle.badge.rawValue)
    }

    func testUserDefaultsValueOverridesDefault() {
        defaults.set(StatusIndicatorStyle.badge.rawValue, forKey: "statusIndicatorStyle")
        XCTAssertEqual(makeStore().statusIndicatorStyle, .badge)
    }

    func testForcedStringOverridesDefault() {
        let managed = InMemoryManagedPreferences(
            [ManagedKey.statusIndicatorStyle: StatusIndicatorStyle.badge.rawValue]
        )
        XCTAssertEqual(makeStore(managed: managed).statusIndicatorStyle, .badge)
    }

    func testForcedOverridesUserDefaults() {
        defaults.set(StatusIndicatorStyle.rail.rawValue, forKey: "statusIndicatorStyle") // user says rail
        let managed = InMemoryManagedPreferences(
            [ManagedKey.statusIndicatorStyle: StatusIndicatorStyle.badge.rawValue] // MDM says badge
        )
        XCTAssertEqual(makeStore(managed: managed).statusIndicatorStyle, .badge) // MDM wins
    }

    func testIsLockedWhenForced() {
        let managed = InMemoryManagedPreferences([ManagedKey.statusIndicatorStyle: "badge"])
        XCTAssertTrue(makeStore(managed: managed).isLocked(ManagedKey.statusIndicatorStyle))
    }

    func testNotLockedWhenUnforced() {
        XCTAssertFalse(makeStore().isLocked(ManagedKey.statusIndicatorStyle))
    }
}

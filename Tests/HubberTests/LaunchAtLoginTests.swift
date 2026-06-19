import Foundation
import XCTest
@testable import Hubber

/// In-memory fake — never touches SMAppService.
final class FakeLaunchAtLogin: LaunchAtLoginManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled: Bool
    private var _calls: [Bool] = []
    init(enabled: Bool = false) {
        _enabled = enabled
    }

    var isEnabled: Bool {
        lock.withLock { _enabled }
    }

    var calls: [Bool] {
        lock.withLock { _calls }
    }

    func setEnabled(_ enabled: Bool) throws {
        lock.withLock { _enabled = enabled
            _calls.append(enabled)
        }
    }
}

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private var defaults: UserDefaults!
    private nonisolated(unsafe) var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "LaunchAtLoginTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultLaunchAtLoginIsFalse() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.launchAtLoginEnabled)
    }

    func testLaunchAtLoginPersists() {
        let store = SettingsStore(defaults: defaults)
        store.launchAtLoginEnabled = true
        XCTAssertTrue(defaults.bool(forKey: "launchAtLogin"))
    }

    func testForcedLaunchAtLoginWinsAndLocks() {
        let managed = InMemoryManagedPreferences([ManagedKey.launchAtLogin: true])
        let store = SettingsStore(defaults: defaults, managed: managed)
        XCTAssertTrue(store.launchAtLoginEnabled)
        XCTAssertTrue(store.isLocked(ManagedKey.launchAtLogin))
    }

    func testFakeServiceRecordsSetCalls() throws {
        let fake = FakeLaunchAtLogin()
        try fake.setEnabled(true)
        XCTAssertTrue(fake.isEnabled)
        XCTAssertEqual(fake.calls, [true])
    }
}

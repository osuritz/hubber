import Foundation
import XCTest
@testable import Hubber

// MARK: - Minimal telemetry sink (avoids TelemetryDeck side effects in tests)

private struct LaunchAtLoginNullTelemetrySink: TelemetrySink {
    func send(_: String, _: [String: String]) {}
}

/// In-memory fake — never touches SMAppService. `failOnSet` simulates a registration failure:
/// the call is recorded but `isEnabled` does not change (mirrors a thrown SMAppService error).
final class FakeLaunchAtLogin: LaunchAtLoginManaging, @unchecked Sendable {
    struct RegistrationError: Error {}

    private let lock = NSLock()
    private var _enabled: Bool
    private var _calls: [Bool] = []
    private let failOnSet: Bool
    init(enabled: Bool = false, failOnSet: Bool = false) {
        _enabled = enabled
        self.failOnSet = failOnSet
    }

    var isEnabled: Bool {
        lock.withLock { _enabled }
    }

    var calls: [Bool] {
        lock.withLock { _calls }
    }

    func setEnabled(_ enabled: Bool) throws {
        if failOnSet {
            lock.withLock { _calls.append(enabled) }
            throw RegistrationError()
        }
        lock.withLock { _enabled = enabled
            _calls.append(enabled)
        }
    }
}

@MainActor
final class LaunchAtLoginTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "LaunchAtLoginTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
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

    // MARK: - HubberStore integration

    func testSetLaunchAtLoginPersistsAndApplies() {
        let settings = SettingsStore(defaults: defaults)
        let fake = FakeLaunchAtLogin()
        let store = HubberStore(
            settings: settings,
            telemetry: Telemetry(sink: LaunchAtLoginNullTelemetrySink()),
            snapshotStore: SnapshotStore(snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("lal-test-\(UUID()).json")),
            defaults: defaults,
            restoreOnInit: false,
            launchAtLogin: fake
        )
        store.setLaunchAtLogin(true)
        XCTAssertTrue(settings.launchAtLoginEnabled)
        XCTAssertTrue(defaults.bool(forKey: "launchAtLogin"))
        XCTAssertEqual(fake.calls, [true])
    }

    func testReconcileLaunchAtLoginAppliesResolvedState() {
        defaults.set(true, forKey: "launchAtLogin")
        let fake = FakeLaunchAtLogin()
        let store = HubberStore(
            settings: SettingsStore(defaults: defaults),
            telemetry: Telemetry(sink: LaunchAtLoginNullTelemetrySink()),
            snapshotStore: SnapshotStore(snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("lal-reconcile-\(UUID()).json")),
            defaults: defaults,
            restoreOnInit: false,
            launchAtLogin: fake
        )
        store.reconcileLaunchAtLogin()
        XCTAssertEqual(fake.calls, [true])
    }

    func testSetLaunchAtLoginIgnoredWhenMDMLocked() {
        let managed = InMemoryManagedPreferences([ManagedKey.launchAtLogin: false])
        let settings = SettingsStore(defaults: defaults, managed: managed)
        let fake = FakeLaunchAtLogin()
        let store = HubberStore(
            settings: settings,
            telemetry: Telemetry(sink: LaunchAtLoginNullTelemetrySink()),
            snapshotStore: SnapshotStore(snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("lal-locked-\(UUID()).json")),
            defaults: defaults,
            restoreOnInit: false,
            launchAtLogin: fake
        )
        store.setLaunchAtLogin(true)
        XCTAssertTrue(fake.calls.isEmpty, "an MDM-locked setting must not be applied by a user action")
        XCTAssertFalse(settings.launchAtLoginEnabled, "the forced value must remain unchanged")
    }

    func testSetLaunchAtLoginPersistsActualStateWhenRegistrationFails() {
        let settings = SettingsStore(defaults: defaults)
        let fake = FakeLaunchAtLogin(failOnSet: true)
        let store = HubberStore(
            settings: settings,
            telemetry: Telemetry(sink: LaunchAtLoginNullTelemetrySink()),
            snapshotStore: SnapshotStore(snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("lal-fail-\(UUID()).json")),
            defaults: defaults,
            restoreOnInit: false,
            launchAtLogin: fake
        )
        store.setLaunchAtLogin(true)
        XCTAssertEqual(fake.calls, [true], "registration was attempted")
        XCTAssertFalse(
            settings.launchAtLoginEnabled,
            "the toggle must reflect the actual (failed) state, not the intent"
        )
        XCTAssertFalse(defaults.bool(forKey: "launchAtLogin"))
    }
}

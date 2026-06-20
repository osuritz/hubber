import Foundation
import XCTest
@testable import Hubber

@MainActor
final class HubberStoreTelemetryGateTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "HubberStoreTelemetryGateTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testAnalyticsToggleGatesTelemetryLiveThroughStore() {
        let spy = SpyTelemetrySink()
        let settings = SettingsStore(defaults: defaults)
        // analyticsEnabled defaults to false
        let gate = GatedTelemetrySink(
            enabled: settings.analyticsEnabled,
            underlying: spy,
            initializeSDK: {}
        )
        let store = HubberStore(
            settings: settings,
            telemetryGate: gate,
            snapshotStore: SnapshotStore(snapshotURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("telemetry-gate-test-\(UUID()).json")),
            defaults: defaults,
            restoreOnInit: false
        )

        // Initially disabled: events must not be forwarded
        store.telemetry.sessionOpened()
        XCTAssertTrue(spy.calls.isEmpty, "Expected no calls while analytics is disabled")

        // Enable analytics — the live subscription should propagate to the gate
        settings.analyticsEnabled = true
        store.telemetry.sessionOpened()
        XCTAssertEqual(spy.calls.count, 1, "Expected 1 call after enabling analytics")

        // Disable analytics — gate should stop forwarding immediately
        settings.analyticsEnabled = false
        store.telemetry.sessionOpened()
        XCTAssertEqual(spy.calls.count, 1, "Expected call count to stay at 1 after disabling analytics")
    }
}

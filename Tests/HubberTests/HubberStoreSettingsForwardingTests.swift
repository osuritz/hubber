import Combine
import Foundation
import XCTest
@testable import Hubber

/// `HubberPopoverView` observes `HubberStore` but reads settings-derived values
/// (e.g. `store.settings.tabBadgeMode`, SLO display). The store must re-publish
/// when its nested `SettingsStore` changes, otherwise the popover renders stale
/// until some unrelated invalidation occurs.
@MainActor
final class HubberStoreSettingsForwardingTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "HubberStoreSettingsForwardingTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    func testStoreEmitsObjectWillChangeWhenSettingsChange() {
        let settings = SettingsStore(defaults: defaults)
        let store = HubberStore(settings: settings, restoreOnInit: false)

        let expectation = expectation(description: "store re-publishes on settings change")
        let cancellable = store.objectWillChange.sink { expectation.fulfill() }

        store.settings.tabBadgeMode =
            store.settings.tabBadgeMode == .needsAttention ? .totalCount : .needsAttention

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}

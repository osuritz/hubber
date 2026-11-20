import XCTest
@testable import Hubber

@MainActor
final class EscapeRoutingTests: XCTestCase {
    private func makeStore() throws -> HubberStore {
        let suite = "EscapeRoutingTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return HubberStore(settings: SettingsStore(defaults: defaults), restoreOnInit: false)
    }

    func testEscapeLeavesSettingsAndIsConsumed() throws {
        let store = try makeStore()
        store.showSettings = true
        XCTAssertTrue(store.handleEscape())
        XCTAssertFalse(store.showSettings)
    }

    func testEscapeOutsideSettingsIsNotConsumed() throws {
        let store = try makeStore()
        XCTAssertFalse(store.handleEscape())
        XCTAssertFalse(store.showSettings)
    }
}

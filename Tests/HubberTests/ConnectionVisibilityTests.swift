import Foundation
import SwiftUI
import XCTest
@testable import Hubber

final class ConnectionVisibilityTests: XCTestCase {
    private let gh = ConnectionID.gitHubDotCom(login: "osuritz")
    private let gl = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")

    func testDefaultEverythingVisible() {
        let v = ConnectionVisibility()
        XCTAssertTrue(v.isVisible(gh))
        XCTAssertTrue(v.isVisible(gl))
    }

    func testHidingThenShowing() {
        let hidden = ConnectionVisibility().setting(gl, visible: false)
        XCTAssertTrue(hidden.isVisible(gh))
        XCTAssertFalse(hidden.isVisible(gl))

        let shown = hidden.setting(gl, visible: true)
        XCTAssertTrue(shown.isVisible(gl))
    }

    func testCodableRoundTrip() throws {
        let v = ConnectionVisibility().setting(gl, visible: false)
        let data = try JSONEncoder().encode(v)
        let decoded = try JSONDecoder().decode(ConnectionVisibility.self, from: data)
        XCTAssertEqual(decoded, v)
        XCTAssertFalse(decoded.isVisible(gl))
    }

    @MainActor
    func testSettingsStorePersistsVisibilityAcrossInstances() throws {
        let suite = "ConnectionVisibilityTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.connectionVisibility.isVisible(gl)) // default visible

        store.connectionVisibility = store.connectionVisibility.setting(gl, visible: false)

        // A fresh store over the same defaults sees the hidden connection.
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertFalse(reopened.connectionVisibility.isVisible(gl))
        XCTAssertTrue(reopened.connectionVisibility.isVisible(gh))
    }

    func testVisibilityAwareAggregateDropsHiddenConnections() {
        let ghData = HubberData(incoming: [Self.incoming(id: "gh-1", repo: "acme/api")], outgoing: [], drafts: [])
        let glData = HubberData(incoming: [Self.incoming(id: "gl-1", repo: "grp/proj")], outgoing: [], drafts: [])
        let items: [(id: ConnectionID, data: HubberData)] = [(gh, ghData), (gl, glData)]

        // All visible → both incoming items.
        let all = ConnectionAggregator.aggregate(items, visibility: ConnectionVisibility())
        XCTAssertEqual(all.incoming.map(\.id).sorted(), ["gh-1", "gl-1"])

        // Hide GitLab → only the GitHub item.
        let hidden = ConnectionVisibility().setting(gl, visible: false)
        let filtered = ConnectionAggregator.aggregate(items, visibility: hidden)
        XCTAssertEqual(filtered.incoming.map(\.id), ["gh-1"])
    }

    private static func incoming(id: String, repo: String) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: repo,
            number: 1,
            title: "t",
            url: nil,
            author: GitHubUser(login: "a", initials: "A", color: .gray),
            sloClockStart: Date(timeIntervalSince1970: 0),
            additions: 0,
            deletions: 0,
            files: 0
        )
    }
}

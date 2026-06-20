import Foundation
import XCTest
@testable import Hubber

// MARK: - SettingsStoreMDMTests

//
// Tests for MDM-over-UserDefaults seam behaviour: forced managed values must
// always win over conflicting UserDefaults values and hardcoded defaults.
// Covers all lockable keys, CSV-string defaultNotificationEvents, rowDensity
// string form, notificationsEnabled-alone composite, bool Int-encoding,
// and ManagedKey literal-value assertions.

@MainActor
final class SettingsStoreMDMTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "SettingsStoreMDMTests-\(UUID())"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeStore(managed: InMemoryManagedPreferences = InMemoryManagedPreferences()) -> SettingsStore {
        SettingsStore(defaults: defaults, managed: managed)
    }

    // MARK: - Forced wins over UserDefaults (MDM-over-UserDefaults seam)

    // sloWindowHours: MDM forced value beats a conflicting UserDefaults value
    func testForcedSloWindowHoursWinsOverUserDefaults() {
        defaults.set(99.0, forKey: "sloWindowHours") // UserDefaults says 99
        let managed = InMemoryManagedPreferences([ManagedKey.sloWindowHours: 2]) // MDM says 2
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.sloHours, 2.0)
    }

    // sloDisplay: MDM forced value beats a conflicting UserDefaults value
    func testForcedSloDisplayWinsOverUserDefaults() {
        defaults.set(SLODisplay.traffic.rawValue, forKey: "sloDisplay") // UserDefaults says traffic
        let managed = InMemoryManagedPreferences([ManagedKey.sloDisplay: "elapsed"]) // MDM says elapsed
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.sloDisplay, .elapsed)
    }

    // badgeMode: MDM forced value beats a conflicting UserDefaults value
    func testForcedBadgeModeWinsOverUserDefaults() {
        defaults.set(BadgeMode.off.rawValue, forKey: "badgeMode") // UserDefaults says off
        let managed = InMemoryManagedPreferences([ManagedKey.badgeMode: BadgeMode.incomingCount.rawValue])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.badgeMode, .incomingCount)
    }

    // tabBadgeMode: MDM forced value beats a conflicting UserDefaults value
    func testForcedTabBadgeModeWinsOverUserDefaults() {
        defaults.set(TabBadgeMode.totalCount.rawValue, forKey: "tabBadgeMode") // UserDefaults says total
        let managed = InMemoryManagedPreferences([ManagedKey.tabBadgeMode: TabBadgeMode.needsAttention.rawValue])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.tabBadgeMode, .needsAttention)
    }

    // incomingMode: MDM forced value beats a conflicting UserDefaults value
    func testForcedIncomingModeWinsOverUserDefaults() {
        defaults.set(IncomingReviewMode.team.rawValue, forKey: "incomingMode") // UserDefaults says team
        let managed = InMemoryManagedPreferences([ManagedKey.incomingMode: "explicit"]) // MDM says explicit
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.incomingMode, .explicit)
    }

    // unresolvedThreadMode: MDM forced value beats a conflicting UserDefaults value
    func testForcedUnresolvedThreadModeWinsOverUserDefaults() {
        defaults.set(UnresolvedThreadMode.changesRequested.rawValue, forKey: "unresolvedThreadMode")
        let managed = InMemoryManagedPreferences([ManagedKey.unresolvedThreadMode: "reviewOnly"])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.unresolvedMode, .reviewOnly)
    }

    // rowDensity: MDM forced Int value beats a conflicting UserDefaults value
    func testForcedRowDensityIntWinsOverUserDefaults() {
        defaults.set(RowDensity.spacious.rawValue, forKey: "rowDensity") // UserDefaults: spacious (3)
        let managed = InMemoryManagedPreferences([ManagedKey.rowDensity: RowDensity.compact.rawValue])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.rowDensity, .compact)
    }

    // notificationsEnabled: MDM forced value beats a conflicting UserDefaults value
    func testForcedNotificationsEnabledWinsOverUserDefaults() {
        defaults.set(false, forKey: "notificationsEnabled") // UserDefaults says false
        let managed = InMemoryManagedPreferences([ManagedKey.notificationsEnabled: true]) // MDM says true
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.notificationsEnabled)
    }

    // crashReportingEnabled: MDM forced value beats a conflicting UserDefaults value
    func testForcedCrashReportingEnabledWinsOverUserDefaults() {
        defaults.set(false, forKey: "crashReportingEnabled")
        let managed = InMemoryManagedPreferences([ManagedKey.crashReportingEnabled: true])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.crashReportingEnabled)
    }

    // providerAllowlist: MDM forced value beats a conflicting UserDefaults value
    func testForcedProviderAllowlistWinsOverUserDefaults() {
        defaults.set(["github.com"], forKey: "providerAllowlist") // UserDefaults has a value
        let managed = InMemoryManagedPreferences([ManagedKey.providerAllowlist: ["github.enterprise.com"]])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.providerAllowlist, ["github.enterprise.com"])
    }

    // allowPersonalGitHub: MDM forced value beats a conflicting UserDefaults value
    func testForcedAllowPersonalGitHubWinsOverUserDefaults() {
        defaults.set(true, forKey: "allowPersonalGitHub") // UserDefaults says true
        let managed = InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: false]) // MDM says false
        let store = makeStore(managed: managed)
        XCTAssertFalse(store.allowPersonalGitHub)
    }

    // defaultNotificationEvents: MDM forced array beats UserDefaults per-type values
    func testForcedDefaultNotificationEventsWinsOverUserDefaults() {
        // UserDefaults has all five enabled
        defaults.set(true, forKey: "notifyNewReview")
        defaults.set(true, forKey: "notifyReviewApproved")
        defaults.set(true, forKey: "notifyChangesRequested")
        defaults.set(true, forKey: "notifyCIFailed")
        defaults.set(true, forKey: "notifyPRMerged")
        // MDM restricts to just two
        let managed = InMemoryManagedPreferences([
            ManagedKey.defaultNotificationEvents: ["changesRequested", "prMerged"],
        ])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.enabledNotificationTypes, [.changesRequested, .prMerged])
    }

    // MARK: - CSV-string defaultNotificationEvents (legacy branch)

    /// Force a plain String "newReview,ciFailed" instead of an array; verify the CSV path.
    func testForcedDefaultNotificationEventsCSVString() {
        let managed = InMemoryManagedPreferences([
            ManagedKey.defaultNotificationEvents: "newReview,ciFailed",
        ])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.enabledNotificationTypes, [.newReview, .ciFailed])
        // All per-type keys report locked because defaultNotificationEvents is forced
        XCTAssertTrue(store.isLocked("notifyNewReview"))
        XCTAssertTrue(store.isLocked("notifyReviewApproved"))
        XCTAssertTrue(store.isLocked("notifyCIFailed"))
        XCTAssertTrue(store.isLocked("notifyChangesRequested"))
        XCTAssertTrue(store.isLocked("notifyPRMerged"))
    }

    // MARK: - rowDensity string form (compact and normal)

    func testForcedRowDensityStringCompact() {
        let managed = InMemoryManagedPreferences([ManagedKey.rowDensity: "compact"])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.rowDensity, .compact)
    }

    func testForcedRowDensityStringNormal() {
        let managed = InMemoryManagedPreferences([ManagedKey.rowDensity: "normal"])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.rowDensity, .normal)
    }

    // MARK: - notificationsEnabled forced true alone (no composite)

    /// When only notificationsEnabled is forced true (no defaultNotificationEvents),
    /// per-type toggles are locked AND enabledNotificationTypes reflects per-type UserDefaults.
    func testForcedNotificationsEnabledTrueAloneLocksPerTypeAndUsesUserDefaults() {
        // Set some per-type flags in UserDefaults
        defaults.set(true, forKey: "notifyNewReview")
        defaults.set(true, forKey: "notifyReviewApproved")
        defaults.set(false, forKey: "notifyChangesRequested")
        defaults.set(false, forKey: "notifyCIFailed")
        defaults.set(false, forKey: "notifyPRMerged")
        let managed = InMemoryManagedPreferences([ManagedKey.notificationsEnabled: true])
        let store = makeStore(managed: managed)
        // All per-type keys are locked because notificationsEnabled is forced
        XCTAssertTrue(store.isLocked("notifyNewReview"))
        XCTAssertTrue(store.isLocked("notifyReviewApproved"))
        XCTAssertTrue(store.isLocked("notifyChangesRequested"))
        XCTAssertTrue(store.isLocked("notifyCIFailed"))
        XCTAssertTrue(store.isLocked("notifyPRMerged"))
        // enabledNotificationTypes uses per-type UserDefaults values (not defaultNotificationEvents)
        XCTAssertEqual(store.enabledNotificationTypes, [.newReview, .reviewApproved])
    }

    // MARK: - providerAllowlist direct forced tests

    func testForcedProviderAllowlistDirectSingleHost() {
        let managed = InMemoryManagedPreferences([ManagedKey.providerAllowlist: ["github.example.com"]])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.providerAllowlist, ["github.example.com"])
        XCTAssertTrue(store.isLocked(ManagedKey.providerAllowlist))
    }

    func testForcedProviderAllowlistMultipleHosts() {
        let managed = InMemoryManagedPreferences([
            ManagedKey.providerAllowlist: ["github.example.com", "github.example2.com"],
        ])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.providerAllowlist, ["github.example.com", "github.example2.com"])
    }

    func testForcedProviderAllowlistEmptyArray() {
        defaults.set(["github.com"], forKey: "providerAllowlist") // UserDefaults has a value
        let managed = InMemoryManagedPreferences([ManagedKey.providerAllowlist: [String]()])
        let store = makeStore(managed: managed)
        // Forced empty array means no host restriction (MDM wins over UserDefaults)
        XCTAssertEqual(store.providerAllowlist, [])
        XCTAssertTrue(store.isLocked(ManagedKey.providerAllowlist))
    }

    // MARK: - allowPersonalGitHub direct forced tests

    func testForcedAllowPersonalGitHubFalse() {
        let managed = InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: false])
        let store = makeStore(managed: managed)
        XCTAssertFalse(store.allowPersonalGitHub)
        XCTAssertTrue(store.isLocked(ManagedKey.allowPersonalGitHub))
    }

    func testForcedAllowPersonalGitHubTrue() {
        defaults.set(false, forKey: "allowPersonalGitHub") // UserDefaults says false
        let managed = InMemoryManagedPreferences([ManagedKey.allowPersonalGitHub: true])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.allowPersonalGitHub)
    }

    // MARK: - bool() Int-encoded boolean (MDM Integer form)

    /// Verify that bool() accepts <integer>1</integer> as true from MDM
    func testBoolHelperAcceptsIntEncodedTrue() {
        let managed = InMemoryManagedPreferences([ManagedKey.analyticsEnabled: 1])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.analyticsEnabled)
        XCTAssertTrue(store.isLocked(ManagedKey.analyticsEnabled))
    }

    /// Verify that bool() accepts <integer>0</integer> as false from MDM
    func testBoolHelperAcceptsIntEncodedFalse() {
        let managed = InMemoryManagedPreferences([ManagedKey.analyticsEnabled: 0])
        let store = makeStore(managed: managed)
        XCTAssertFalse(store.analyticsEnabled)
        XCTAssertTrue(store.isLocked(ManagedKey.analyticsEnabled))
    }

    // MARK: - ManagedKey literal-value assertions

    func testManagedKeyLiteralValues() {
        XCTAssertEqual(ManagedKey.sloEnabled, "sloEnabled")
        XCTAssertEqual(ManagedKey.sloWindowHours, "sloWindowHours")
        XCTAssertEqual(ManagedKey.sloDisplay, "sloDisplay")
        XCTAssertEqual(ManagedKey.badgeMode, "badgeMode")
        XCTAssertEqual(ManagedKey.incomingMode, "incomingMode")
        XCTAssertEqual(ManagedKey.unresolvedThreadMode, "unresolvedThreadMode")
        XCTAssertEqual(ManagedKey.rowDensity, "rowDensity")
        XCTAssertEqual(ManagedKey.analyticsEnabled, "analyticsEnabled")
        XCTAssertEqual(ManagedKey.crashReportingEnabled, "crashReportingEnabled")
        XCTAssertEqual(ManagedKey.notificationsEnabled, "notificationsEnabled")
        XCTAssertEqual(ManagedKey.defaultNotificationEvents, "defaultNotificationEvents")
        XCTAssertEqual(ManagedKey.providerAllowlist, "providerAllowlist")
        XCTAssertEqual(ManagedKey.allowPersonalGitHub, "allowPersonalGitHub")
    }
}

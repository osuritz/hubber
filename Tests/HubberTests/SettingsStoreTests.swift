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

    // MARK: - Helper

    /// Returns a fresh SettingsStore using a fresh UserDefaults suite + the given managed prefs.
    private func makeStore(managed: InMemoryManagedPreferences = InMemoryManagedPreferences()) -> SettingsStore {
        SettingsStore(defaults: defaults, managed: managed)
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

    // MARK: - badgeMode

    func testDefaultBadgeModeIsAttentionNeeded() {
        XCTAssertEqual(sut.badgeMode, .attentionNeeded)
    }

    func testBadgeModePersistedToUserDefaults() {
        sut.badgeMode = .incomingCount
        XCTAssertEqual(defaults.string(forKey: "badgeMode"), BadgeMode.incomingCount.rawValue)
    }

    func testBadgeModeOffPersistedToUserDefaults() {
        sut.badgeMode = .off
        XCTAssertEqual(defaults.string(forKey: "badgeMode"), BadgeMode.off.rawValue)
    }

    func testUserDefaultsValueOverridesBadgeModeDefault() {
        defaults.set(BadgeMode.incomingCount.rawValue, forKey: "badgeMode")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.badgeMode, .incomingCount)
    }

    func testUserDefaultsOffValueOverridesBadgeModeDefault() {
        defaults.set(BadgeMode.off.rawValue, forKey: "badgeMode")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.badgeMode, .off)
    }

    // MARK: - Notification settings (#37)

    func testDefaultNotificationsEnabledIsTrue() {
        XCTAssertTrue(sut.notificationsEnabled)
    }

    func testDefaultEnabledNotificationTypesContainsOnlyNewReview() {
        XCTAssertEqual(sut.enabledNotificationTypes, [.newReview])
    }

    func testDefaultNotifyNewReviewIsTrue() {
        XCTAssertTrue(sut.notifyNewReview)
    }

    func testDefaultNotifyReviewApprovedIsFalse() {
        XCTAssertFalse(sut.notifyReviewApproved)
    }

    func testDefaultNotifyChangesRequestedIsFalse() {
        XCTAssertFalse(sut.notifyChangesRequested)
    }

    func testDefaultNotifyCIFailedIsFalse() {
        XCTAssertFalse(sut.notifyCIFailed)
    }

    func testDefaultNotifyPRMergedIsFalse() {
        XCTAssertFalse(sut.notifyPRMerged)
    }

    func testNotificationsEnabledPersistedToUserDefaults() {
        sut.notificationsEnabled = false
        XCTAssertFalse(defaults.bool(forKey: "notificationsEnabled"))
    }

    func testNotifyNewReviewPersistedToUserDefaults() {
        sut.notifyNewReview = false
        XCTAssertFalse(defaults.bool(forKey: "notifyNewReview"))
    }

    func testNotifyReviewApprovedPersistedToUserDefaults() {
        sut.notifyReviewApproved = true
        XCTAssertTrue(defaults.bool(forKey: "notifyReviewApproved"))
    }

    func testEnabledNotificationTypesReflectsPerTypeFlags() {
        sut.notifyReviewApproved = true
        sut.notifyCIFailed = true
        let types = sut.enabledNotificationTypes
        XCTAssertTrue(types.contains(.newReview))
        XCTAssertTrue(types.contains(.reviewApproved))
        XCTAssertTrue(types.contains(.ciFailed))
        XCTAssertFalse(types.contains(.changesRequested))
        XCTAssertFalse(types.contains(.prMerged))
    }

    func testNotificationsDisabledMakesEnabledTypesEmpty() {
        sut.notifyNewReview = true
        sut.notifyReviewApproved = true
        sut.notificationsEnabled = false
        XCTAssertTrue(sut.enabledNotificationTypes.isEmpty)
    }

    func testUserDefaultsNotificationsEnabledOverride() {
        defaults.set(false, forKey: "notificationsEnabled")
        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.notificationsEnabled)
    }

    func testUserDefaultsNotifyReviewApprovedOverride() {
        defaults.set(true, forKey: "notifyReviewApproved")
        let store = SettingsStore(defaults: defaults)
        XCTAssertTrue(store.notifyReviewApproved)
    }

    // MARK: - defaultNotificationEvents composite key (D)

    // Note: CFPreferencesAppValueIsForced cannot be forced in unit tests (requires system MDM).
    // These tests verify the per-type UserDefaults path (used when MDM key is not forced)
    // and confirm that enabledNotificationTypes reflects a matching parsed set.

    func testDefaultNotificationEventsViaUserDefaultsAllTypes() {
        // Simulate what the MDM composite key would configure: all types enabled
        defaults.set(true, forKey: "notifyNewReview")
        defaults.set(true, forKey: "notifyReviewApproved")
        defaults.set(true, forKey: "notifyChangesRequested")
        defaults.set(true, forKey: "notifyCIFailed")
        defaults.set(true, forKey: "notifyPRMerged")
        let store = SettingsStore(defaults: defaults)
        let expected: Set<NotificationEventType> = [
            .newReview, .reviewApproved, .changesRequested, .ciFailed, .prMerged,
        ]
        XCTAssertEqual(store.enabledNotificationTypes, expected)
    }

    func testDefaultNotificationEventsViaUserDefaultsSubset() {
        // Simulate composite key "newReview,ciFailed"
        defaults.set(true, forKey: "notifyNewReview")
        defaults.set(false, forKey: "notifyReviewApproved")
        defaults.set(false, forKey: "notifyChangesRequested")
        defaults.set(true, forKey: "notifyCIFailed")
        defaults.set(false, forKey: "notifyPRMerged")
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.enabledNotificationTypes, [.newReview, .ciFailed])
    }

    // MARK: - Task 2: Forced managed values override UserDefaults + hardcoded defaults

    // sloEnabled — managed key "sloEnabled"; persistence key "reviewSLOEnabled"
    func testForcedSloEnabledFalseOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.sloEnabled: false])
        let store = makeStore(managed: managed)
        XCTAssertFalse(store.sloEnabled)
    }

    func testForcedSloEnabledOverridesUserDefaults() {
        defaults.set(false, forKey: "reviewSLOEnabled")  // UserDefaults says false
        let managed = InMemoryManagedPreferences([ManagedKey.sloEnabled: true])  // MDM says true
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.sloEnabled)  // MDM wins
    }

    func testIsLockedReviewSLOEnabledWhenSloEnabledForced() {
        let managed = InMemoryManagedPreferences([ManagedKey.sloEnabled: true])
        let store = makeStore(managed: managed)
        // The UI key is "reviewSLOEnabled" (UserDefaults persistence key)
        XCTAssertTrue(store.isLocked("reviewSLOEnabled"))
        // Also true for the managed key itself
        XCTAssertTrue(store.isLocked(ManagedKey.sloEnabled))
    }

    func testIsLockedReviewSLOEnabledFalseWhenNotForced() {
        let store = makeStore(managed: InMemoryManagedPreferences())
        XCTAssertFalse(store.isLocked("reviewSLOEnabled"))
    }

    // sloWindowHours
    func testForcedSloWindowHoursOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.sloWindowHours: 2])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.sloHours, 2.0)
    }

    func testIsLockedSloWindowHours() {
        let managed = InMemoryManagedPreferences([ManagedKey.sloWindowHours: 8])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.sloWindowHours))
    }

    // sloDisplay
    func testForcedSloDisplayOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.sloDisplay: SLODisplay.elapsed.rawValue])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.sloDisplay, .elapsed)
    }

    func testIsLockedSloDisplay() {
        let managed = InMemoryManagedPreferences([ManagedKey.sloDisplay: "elapsed"])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.sloDisplay))
    }

    // badgeMode
    func testForcedBadgeModeOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.badgeMode: BadgeMode.off.rawValue])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.badgeMode, .off)
    }

    func testIsLockedBadgeMode() {
        let managed = InMemoryManagedPreferences([ManagedKey.badgeMode: "off"])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.badgeMode))
    }

    // incomingMode
    func testForcedIncomingModeOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.incomingMode: IncomingReviewMode.team.rawValue])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.incomingMode, .team)
    }

    func testIsLockedIncomingMode() {
        let managed = InMemoryManagedPreferences([ManagedKey.incomingMode: "team"])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.incomingMode))
    }

    // unresolvedThreadMode
    func testForcedUnresolvedThreadModeOverridesDefault() {
        let managed = InMemoryManagedPreferences(
            [ManagedKey.unresolvedThreadMode: UnresolvedThreadMode.changesRequested.rawValue]
        )
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.unresolvedMode, .changesRequested)
    }

    func testIsLockedUnresolvedThreadMode() {
        let managed = InMemoryManagedPreferences([ManagedKey.unresolvedThreadMode: "reviewOnly"])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.unresolvedThreadMode))
    }

    // rowDensity — accepts Int rawValue
    func testForcedRowDensityIntOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.rowDensity: RowDensity.compact.rawValue])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.rowDensity, .compact)
    }

    // rowDensity — accepts String ("compact"|"normal"|"spacious")
    func testForcedRowDensityStringOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.rowDensity: "spacious"])
        let store = makeStore(managed: managed)
        XCTAssertEqual(store.rowDensity, .spacious)
    }

    func testIsLockedRowDensity() {
        let managed = InMemoryManagedPreferences([ManagedKey.rowDensity: 1])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.rowDensity))
    }

    // notificationsEnabled
    func testForcedNotificationsEnabledFalseOverridesDefault() {
        let managed = InMemoryManagedPreferences([ManagedKey.notificationsEnabled: false])
        let store = makeStore(managed: managed)
        XCTAssertFalse(store.notificationsEnabled)
    }

    func testIsLockedNotificationsEnabled() {
        let managed = InMemoryManagedPreferences([ManagedKey.notificationsEnabled: false])
        let store = makeStore(managed: managed)
        XCTAssertTrue(store.isLocked(ManagedKey.notificationsEnabled))
    }

    // Unforced key → not locked
    func testIsLockedReturnsFalseForUnforcedKey() {
        let store = makeStore(managed: InMemoryManagedPreferences())
        XCTAssertFalse(store.isLocked(ManagedKey.badgeMode))
        XCTAssertFalse(store.isLocked(ManagedKey.sloEnabled))
        XCTAssertFalse(store.isLocked(ManagedKey.notificationsEnabled))
    }
}

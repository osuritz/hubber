import CoreFoundation
import Foundation

// MARK: - ManagedPreferences protocol

//
// Injectable seam for MDM managed-preference reads. The real implementation calls
// CFPreferences; the test fake uses an in-memory dictionary.
//
// Background on the managed domain: `com.hubber.app` is deliberately decoupled from
// the app bundle identifier (`com.osuritz.hubber`) so that a single configuration
// profile works across both the Standard and MAS build variants and survives bundle-id
// changes. macOS forced/managed preferences are keyed by whatever domain string the
// configuration profile declares (`/Library/Managed Preferences/<user>/<domain>.plist`),
// so reading from `com.hubber.app` is correct and intentional. Do not change it to the
// bundle id.
//
// Forced values are resolved at launch (CFPreferences re-reads on next launch). There is
// no live-reload mechanism — document this to IT.

protocol ManagedPreferences: Sendable {
    /// Returns true when the key is forced by MDM for the managed domain.
    func isForced(_ key: String) -> Bool

    /// Returns the managed value for the key, or nil when not present / not forced.
    func value(_ key: String) -> Any?
}

// MARK: - CFManagedPreferences (production)

/// Reads forced/managed preferences from the `com.hubber.app` domain via CoreFoundation.
///
/// This type is the only place in the codebase that calls CFPreferencesAppValueIsForced
/// and CFPreferencesCopyAppValue — all SettingsStore reads route through it.
struct CFManagedPreferences: ManagedPreferences {
    /// The IT-facing managed-preferences domain. One profile works for all build variants.
    ///
    /// CFString is not Sendable in Swift 6, so we keep the domain as a plain String
    /// constant and bridge to CFString at the call site to avoid a global-state warning.
    static let domainString = "com.hubber.app"

    func isForced(_ key: String) -> Bool {
        CFPreferencesAppValueIsForced(key as CFString, Self.domainString as CFString)
    }

    func value(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, Self.domainString as CFString) as Any?
    }
}

// MARK: - ManagedKey registry (single source of truth)

//
// Maps PRD-documented IT-facing key names to constants. The managed-key name is the
// IT-facing contract and must match the PRD/profile exactly. UserDefaults persistence
// keys (where different) are kept in SettingsStore to avoid migrating existing users'
// data. Centralising the mapping here prevents code and docs from drifting.
//
// Full table (matches PRD §Enterprise/MDM):
//
//   Managed key                 Type         UserDefaults key        SettingsStore property
//   sloEnabled                  Bool         reviewSLOEnabled        sloEnabled
//   sloWindowHours              Int          sloWindowHours          sloHours
//   sloDisplay                  String       sloDisplay              sloDisplay
//   badgeMode                   String       badgeMode               badgeMode
//   incomingMode                String       incomingMode            incomingMode
//   unresolvedThreadMode        String       unresolvedThreadMode    unresolvedMode
//   rowDensity                  String|Int   rowDensity              rowDensity
//   analyticsEnabled            Bool         analyticsEnabled        analyticsEnabled
//   crashReportingEnabled       Bool         crashReportingEnabled   crashReportingEnabled
//   notificationsEnabled        Bool         notificationsEnabled    notificationsEnabled
//   defaultNotificationEvents   [String]     per-type notify*        enabledNotificationTypes
//   providerAllowlist           [String]     providerAllowlist       providerAllowlist
//   allowPersonalGitHub         Bool         allowPersonalGitHub     allowPersonalGitHub
//   launchAtLogin               Bool         launchAtLogin           launchAtLoginEnabled
//
// rowDensity: accepts both Int rawValue and String ("compact"|"normal"|"spacious") in profiles;
// SettingsStore resolves both forms so IT can write a human-readable profile.

enum ManagedKey {
    // SLO
    static let sloEnabled = "sloEnabled"
    static let sloWindowHours = "sloWindowHours"
    static let sloDisplay = "sloDisplay"

    // Appearance / badge
    static let badgeMode = "badgeMode"
    static let tabBadgeMode = "tabBadgeMode"
    static let rowDensity = "rowDensity"

    // PR modes
    static let incomingMode = "incomingMode"
    static let unresolvedThreadMode = "unresolvedThreadMode"

    // Telemetry (kill-switches)
    static let analyticsEnabled = "analyticsEnabled"
    static let crashReportingEnabled = "crashReportingEnabled"

    // Notifications
    static let notificationsEnabled = "notificationsEnabled"
    static let defaultNotificationEvents = "defaultNotificationEvents"

    // Provider access
    static let providerAllowlist = "providerAllowlist"
    static let allowPersonalGitHub = "allowPersonalGitHub"

    /// Launch at login
    static let launchAtLogin = "launchAtLogin"
}

import CoreFoundation
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private static let managedDomain = "com.hubber.app" as CFString

    private let defaults: UserDefaults

    // MARK: - SLO

    @Published var sloEnabled: Bool {
        didSet { defaults.set(sloEnabled, forKey: "reviewSLOEnabled") }
    }

    @Published var sloHours: Double {
        didSet { defaults.set(sloHours, forKey: "sloWindowHours") }
    }

    @Published var sloDisplay: SLODisplay {
        didSet { defaults.set(sloDisplay.rawValue, forKey: "sloDisplay") }
    }

    // MARK: - Incoming

    @Published var incomingMode: IncomingReviewMode {
        didSet { defaults.set(incomingMode.rawValue, forKey: "incomingMode") }
    }

    // MARK: - Outgoing

    @Published var unresolvedMode: UnresolvedThreadMode {
        didSet { defaults.set(unresolvedMode.rawValue, forKey: "unresolvedThreadMode") }
    }

    // MARK: - Appearance

    @Published var rowDensity: RowDensity {
        didSet { defaults.set(rowDensity.rawValue, forKey: "rowDensity") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        sloEnabled = Self.bool(key: "reviewSLOEnabled", defaults: defaults, fallback: true)
        sloHours = Self.double(key: "sloWindowHours", defaults: defaults, fallback: 4.0)
        sloDisplay = SLODisplay(
            rawValue: Self.string(
                key: "sloDisplay",
                defaults: defaults,
                fallback: SLODisplay.remaining.rawValue
            )
        ) ?? .remaining
        incomingMode = IncomingReviewMode(
            rawValue: Self.string(
                key: "incomingMode",
                defaults: defaults,
                fallback: IncomingReviewMode.explicit.rawValue
            )
        ) ?? .explicit
        unresolvedMode = UnresolvedThreadMode(
            rawValue: Self.string(
                key: "unresolvedThreadMode",
                defaults: defaults,
                fallback: UnresolvedThreadMode.allOpen.rawValue
            )
        ) ?? .allOpen
        rowDensity = RowDensity(
            rawValue: Self.int(key: "rowDensity", defaults: defaults, fallback: RowDensity.normal.rawValue)
        ) ?? .normal
    }

    /// Returns true when a key is locked via MDM managed preferences.
    func isLocked(_ key: String) -> Bool {
        CFPreferencesAppValueIsForced(key as CFString, Self.managedDomain)
    }

    /// SLO window in hours for a given repo. Per-repo overrides slot in here (backlog).
    func sloHours(for repo: String) -> Double {
        sloHours
    }

    // MARK: - MDM → UserDefaults → default priority

    private static func string(key: String, defaults: UserDefaults, fallback: String) -> String {
        if CFPreferencesAppValueIsForced(key as CFString, managedDomain),
           let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? String {
            return managed
        }
        return defaults.string(forKey: key) ?? fallback
    }

    private static func bool(key: String, defaults: UserDefaults, fallback: Bool) -> Bool {
        if CFPreferencesAppValueIsForced(key as CFString, managedDomain),
           let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? Bool {
            return managed
        }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private static func double(key: String, defaults: UserDefaults, fallback: Double) -> Double {
        if CFPreferencesAppValueIsForced(key as CFString, managedDomain),
           let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? Double {
            return managed
        }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private static func int(key: String, defaults: UserDefaults, fallback: Int) -> Int {
        if CFPreferencesAppValueIsForced(key as CFString, managedDomain),
           let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? Int {
            return managed
        }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.integer(forKey: key)
    }
}

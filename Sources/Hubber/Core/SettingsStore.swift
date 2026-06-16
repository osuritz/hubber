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

    // MARK: - Menubar badge

    @Published var badgeMode: BadgeMode {
        didSet { defaults.set(badgeMode.rawValue, forKey: "badgeMode") }
    }

    // MARK: - Appearance

    @Published var rowDensity: RowDensity {
        didSet { defaults.set(rowDensity.rawValue, forKey: "rowDensity") }
    }

    // MARK: - Notifications (#37)

    /// Master toggle — when false, no notifications are sent regardless of per-type flags.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    @Published var notifyNewReview: Bool {
        didSet { defaults.set(notifyNewReview, forKey: "notifyNewReview") }
    }

    @Published var notifyReviewApproved: Bool {
        didSet { defaults.set(notifyReviewApproved, forKey: "notifyReviewApproved") }
    }

    @Published var notifyChangesRequested: Bool {
        didSet { defaults.set(notifyChangesRequested, forKey: "notifyChangesRequested") }
    }

    @Published var notifyCIFailed: Bool {
        didSet { defaults.set(notifyCIFailed, forKey: "notifyCIFailed") }
    }

    @Published var notifyPRMerged: Bool {
        didSet { defaults.set(notifyPRMerged, forKey: "notifyPRMerged") }
    }

    /// The set of enabled event types (empty when `notificationsEnabled == false`).
    var enabledNotificationTypes: Set<NotificationEventType> {
        guard notificationsEnabled else { return [] }
        var types: Set<NotificationEventType> = []
        if notifyNewReview { types.insert(.newReview) }
        if notifyReviewApproved { types.insert(.reviewApproved) }
        if notifyChangesRequested { types.insert(.changesRequested) }
        if notifyCIFailed { types.insert(.ciFailed) }
        if notifyPRMerged { types.insert(.prMerged) }
        return types
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
        badgeMode = BadgeMode(
            rawValue: Self.string(
                key: "badgeMode",
                defaults: defaults,
                fallback: BadgeMode.attentionNeeded.rawValue
            )
        ) ?? .attentionNeeded
        notificationsEnabled = Self.bool(key: "notificationsEnabled", defaults: defaults, fallback: true)
        let perType = Self.resolvePerTypeFlags(defaults: defaults)
        notifyNewReview = perType.contains(.newReview)
        notifyReviewApproved = perType.contains(.reviewApproved)
        notifyChangesRequested = perType.contains(.changesRequested)
        notifyCIFailed = perType.contains(.ciFailed)
        notifyPRMerged = perType.contains(.prMerged)
    }

    /// Resolves per-type notification flags.
    /// The MDM composite key `defaultNotificationEvents` (comma-separated rawValues) takes
    /// priority when forced; otherwise per-type UserDefaults keys are used (#D).
    private static func resolvePerTypeFlags(defaults: UserDefaults) -> Set<NotificationEventType> {
        let compositeKey = "defaultNotificationEvents" as CFString
        if
            CFPreferencesAppValueIsForced(compositeKey, managedDomain),
            let raw = CFPreferencesCopyAppValue(compositeKey, managedDomain) as? String {
            return Set(
                raw.split(separator: ",")
                    .map { $0.trimmingCharacters(in: CharacterSet.whitespaces) }
                    .compactMap { NotificationEventType(rawValue: String($0)) }
            )
        }
        var types = Set<NotificationEventType>()
        if Self.bool(key: "notifyNewReview", defaults: defaults, fallback: true) { types.insert(.newReview) }
        if Self.bool(key: "notifyReviewApproved", defaults: defaults, fallback: false) { types.insert(.reviewApproved) }
        if Self.bool(key: "notifyChangesRequested", defaults: defaults, fallback: false) {
            types.insert(.changesRequested)
        }
        if Self.bool(key: "notifyCIFailed", defaults: defaults, fallback: false) { types.insert(.ciFailed) }
        if Self.bool(key: "notifyPRMerged", defaults: defaults, fallback: false) { types.insert(.prMerged) }
        return types
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
        if
            CFPreferencesAppValueIsForced(key as CFString, managedDomain),
            let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? String {
            return managed
        }
        return defaults.string(forKey: key) ?? fallback
    }

    private static func bool(key: String, defaults: UserDefaults, fallback: Bool) -> Bool {
        if
            CFPreferencesAppValueIsForced(key as CFString, managedDomain),
            let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? Bool {
            return managed
        }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private static func double(key: String, defaults: UserDefaults, fallback: Double) -> Double {
        if
            CFPreferencesAppValueIsForced(key as CFString, managedDomain),
            let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? Double {
            return managed
        }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.double(forKey: key)
    }

    private static func int(key: String, defaults: UserDefaults, fallback: Int) -> Int {
        if
            CFPreferencesAppValueIsForced(key as CFString, managedDomain),
            let managed = CFPreferencesCopyAppValue(key as CFString, managedDomain) as? Int {
            return managed
        }
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.integer(forKey: key)
    }
}

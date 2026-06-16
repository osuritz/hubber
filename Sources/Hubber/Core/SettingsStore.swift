import CoreFoundation
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    /// Injectable seam for MDM managed-preference reads. Production uses CFManagedPreferences;
    /// tests inject InMemoryManagedPreferences to exercise all enforcement paths.
    private let managed: any ManagedPreferences

    // MARK: - SLO
    //
    // Note: the managed key is "sloEnabled" (PRD / IT-facing) but the UserDefaults
    // persistence key is "reviewSLOEnabled" (kept to avoid migrating existing user data).
    // isLocked("reviewSLOEnabled") delegates to the "sloEnabled" managed key.

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

    init(defaults: UserDefaults = .standard, managed: any ManagedPreferences = CFManagedPreferences()) {
        self.defaults = defaults
        self.managed = managed

        // Resolve all setting values through MDM seam → UserDefaults → hardcoded default.
        sloEnabled = Self.resolveSloEnabled(defaults: defaults, managed: managed)
        sloHours = Self.resolveSloHours(defaults: defaults, managed: managed)
        sloDisplay = Self.resolveSloDisplay(defaults: defaults, managed: managed)
        incomingMode = Self.resolveIncomingMode(defaults: defaults, managed: managed)
        unresolvedMode = Self.resolveUnresolvedMode(defaults: defaults, managed: managed)
        rowDensity = Self.resolveRowDensity(defaults: defaults, managed: managed)
        badgeMode = Self.resolveBadgeMode(defaults: defaults, managed: managed)
        notificationsEnabled = Self.bool(
            managedKey: ManagedKey.notificationsEnabled,
            defaultsKey: ManagedKey.notificationsEnabled,
            defaults: defaults,
            managed: managed,
            fallback: true
        )
        let perType = Self.resolvePerTypeFlags(defaults: defaults, managed: managed)
        notifyNewReview = perType.contains(.newReview)
        notifyReviewApproved = perType.contains(.reviewApproved)
        notifyChangesRequested = perType.contains(.changesRequested)
        notifyCIFailed = perType.contains(.ciFailed)
        notifyPRMerged = perType.contains(.prMerged)
    }

    // MARK: - isLocked
    //
    // Maps UI / UserDefaults keys to their managed-key equivalents. The split exists
    // because "reviewSLOEnabled" (UserDefaults) corresponds to "sloEnabled" (MDM PRD key).
    // All other keys share their name between the two layers.

    /// Returns true when the given key is locked by MDM managed preferences.
    ///
    /// Pass either the UserDefaults persistence key (e.g. "reviewSLOEnabled") or the
    /// managed key (e.g. "sloEnabled") — both map to the same lock check.
    func isLocked(_ key: String) -> Bool {
        // "reviewSLOEnabled" is the UserDefaults persistence key for the "sloEnabled" managed key.
        let managedKey = (key == "reviewSLOEnabled") ? ManagedKey.sloEnabled : key
        return managed.isForced(managedKey)
    }

    // MARK: - Per-repo SLO override (backlog)

    /// SLO window in hours for a given repo. Per-repo overrides slot in here (backlog).
    func sloHours(for repo: String) -> Double {
        sloHours
    }

    // MARK: - Per-field resolution helpers (called only from init)

    private static func resolveSloEnabled(defaults: UserDefaults, managed: any ManagedPreferences) -> Bool {
        bool(
            managedKey: ManagedKey.sloEnabled,
            defaultsKey: "reviewSLOEnabled",
            defaults: defaults,
            managed: managed,
            fallback: true
        )
    }

    private static func resolveSloHours(defaults: UserDefaults, managed: any ManagedPreferences) -> Double {
        double(
            managedKey: ManagedKey.sloWindowHours,
            defaultsKey: ManagedKey.sloWindowHours,
            defaults: defaults,
            managed: managed,
            fallback: 4.0
        )
    }

    private static func resolveSloDisplay(defaults: UserDefaults, managed: any ManagedPreferences) -> SLODisplay {
        SLODisplay(rawValue: string(
            managedKey: ManagedKey.sloDisplay,
            defaultsKey: ManagedKey.sloDisplay,
            defaults: defaults,
            managed: managed,
            fallback: SLODisplay.remaining.rawValue
        )) ?? .remaining
    }

    private static func resolveIncomingMode(
        defaults: UserDefaults,
        managed: any ManagedPreferences
    ) -> IncomingReviewMode {
        IncomingReviewMode(rawValue: string(
            managedKey: ManagedKey.incomingMode,
            defaultsKey: ManagedKey.incomingMode,
            defaults: defaults,
            managed: managed,
            fallback: IncomingReviewMode.explicit.rawValue
        )) ?? .explicit
    }

    private static func resolveUnresolvedMode(
        defaults: UserDefaults,
        managed: any ManagedPreferences
    ) -> UnresolvedThreadMode {
        UnresolvedThreadMode(rawValue: string(
            managedKey: ManagedKey.unresolvedThreadMode,
            defaultsKey: ManagedKey.unresolvedThreadMode,
            defaults: defaults,
            managed: managed,
            fallback: UnresolvedThreadMode.allOpen.rawValue
        )) ?? .allOpen
    }

    private static func resolveBadgeMode(defaults: UserDefaults, managed: any ManagedPreferences) -> BadgeMode {
        BadgeMode(rawValue: string(
            managedKey: ManagedKey.badgeMode,
            defaultsKey: ManagedKey.badgeMode,
            defaults: defaults,
            managed: managed,
            fallback: BadgeMode.attentionNeeded.rawValue
        )) ?? .attentionNeeded
    }

    // MARK: - MDM → UserDefaults → default priority (via injected seam)

    private static func string(
        managedKey: String,
        defaultsKey: String,
        defaults: UserDefaults,
        managed: any ManagedPreferences,
        fallback: String
    ) -> String {
        if managed.isForced(managedKey), let v = managed.value(managedKey) as? String {
            return v
        }
        return defaults.string(forKey: defaultsKey) ?? fallback
    }

    private static func bool(
        managedKey: String,
        defaultsKey: String,
        defaults: UserDefaults,
        managed: any ManagedPreferences,
        fallback: Bool
    ) -> Bool {
        if managed.isForced(managedKey), let v = managed.value(managedKey) as? Bool {
            return v
        }
        guard defaults.object(forKey: defaultsKey) != nil else { return fallback }
        return defaults.bool(forKey: defaultsKey)
    }

    private static func double(
        managedKey: String,
        defaultsKey: String,
        defaults: UserDefaults,
        managed: any ManagedPreferences,
        fallback: Double
    ) -> Double {
        if managed.isForced(managedKey) {
            // Accept both Double and Int from managed profiles
            if let v = managed.value(managedKey) as? Double { return v }
            if let v = managed.value(managedKey) as? Int { return Double(v) }
        }
        guard defaults.object(forKey: defaultsKey) != nil else { return fallback }
        return defaults.double(forKey: defaultsKey)
    }

    /// Resolves `rowDensity` from the managed seam (accepts Int rawValue or a String label)
    /// before falling back to UserDefaults and the hardcoded default.
    ///
    /// IT can write either `rowDensity = 1` (Int rawValue) or `rowDensity = "compact"` (String)
    /// in a configuration profile; both are accepted so the profile is human-readable.
    private static func resolveRowDensity(defaults: UserDefaults, managed: any ManagedPreferences) -> RowDensity {
        if managed.isForced(ManagedKey.rowDensity) {
            // Int rawValue path
            if let intVal = managed.value(ManagedKey.rowDensity) as? Int,
               let density = RowDensity(rawValue: intVal) {
                return density
            }
            // String label path: "compact" | "normal" | "spacious"
            if let strVal = managed.value(ManagedKey.rowDensity) as? String {
                switch strVal.lowercased() {
                case "compact": return .compact
                case "normal": return .normal
                case "spacious": return .spacious
                default: break
                }
            }
        }
        let raw = defaults.object(forKey: ManagedKey.rowDensity) != nil
            ? defaults.integer(forKey: ManagedKey.rowDensity)
            : RowDensity.normal.rawValue
        return RowDensity(rawValue: raw) ?? .normal
    }

    /// Resolves per-type notification flags.
    /// The MDM composite key `defaultNotificationEvents` (array of rawValues or csv string) takes
    /// priority when forced; otherwise per-type UserDefaults keys are used.
    private static func resolvePerTypeFlags(
        defaults: UserDefaults,
        managed: any ManagedPreferences
    ) -> Set<NotificationEventType> {
        if managed.isForced(ManagedKey.defaultNotificationEvents) {
            // Array form (preferred in profiles)
            if let arr = managed.value(ManagedKey.defaultNotificationEvents) as? [String] {
                return Set(arr.compactMap { NotificationEventType(rawValue: $0) })
            }
            // Legacy csv String form
            if let raw = managed.value(ManagedKey.defaultNotificationEvents) as? String {
                return Set(
                    raw.split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .compactMap { NotificationEventType(rawValue: String($0)) }
                )
            }
        }
        // Per-type UserDefaults fallback
        var types = Set<NotificationEventType>()
        let resolveFlag = { (key: String, fallback: Bool) -> Bool in
            bool(managedKey: key, defaultsKey: key, defaults: defaults, managed: managed, fallback: fallback)
        }
        if resolveFlag("notifyNewReview", true) { types.insert(.newReview) }
        if resolveFlag("notifyReviewApproved", false) { types.insert(.reviewApproved) }
        if resolveFlag("notifyChangesRequested", false) { types.insert(.changesRequested) }
        if resolveFlag("notifyCIFailed", false) { types.insert(.ciFailed) }
        if resolveFlag("notifyPRMerged", false) { types.insert(.prMerged) }
        return types
    }
}

import Foundation

// MARK: - App Group ID

public let appGroupID = "group.com.osuritz.hubber"

// MARK: - WidgetSnapshotStore

/// Cross-process store for the widget's shared snapshot, backed by a **JSON file in the App
/// Group container** (`FileManager`). A plain file read is deterministic across processes (no
/// `cfprefsd` propagation, unlike `UserDefaults(suiteName:)` which proved unreliable cross-process).
///
/// IMPORTANT — see the "Data path" findings in
/// `docs/superpowers/specs/2026-06-22-pr-widget-design.md`: the App Group must be a *real,
/// registered* group for the host and widget to actually share this file. Under a **free Personal
/// Team** the container exists and `containerURL(...)` resolves, but the cross-app sandbox grant is
/// not enforced, so the widget reads `nil`. Live data sharing therefore requires a **paid Developer
/// Program** account with a portal-registered App Group (the M4b signing gate). Build, discovery,
/// and render all work without it.
public final class WidgetSnapshotStore: Sendable {
    private let fileURL: URL

    /// Designated initialiser for testing: point at any writable directory.
    public init(containerURL: URL) {
        fileURL = containerURL.appendingPathComponent("snapshot.json")
    }

    /// Convenience initialiser backed by the real App Group container.
    /// Returns `nil` when the container is unavailable (no entitlement / unsigned build).
    public init?() {
        guard
            let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else { return nil }
        fileURL = container.appendingPathComponent("snapshot.json")
    }

    // MARK: - Write

    /// Atomically writes the snapshot as JSON. Throws on encode or I/O failure.
    public func write(_ snapshot: WidgetSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - Read

    /// Returns the stored snapshot, or `nil` if absent, corrupt, or unreadable. Never throws.
    public func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

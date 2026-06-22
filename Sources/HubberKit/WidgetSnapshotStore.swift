import Foundation

// MARK: - App Group ID

public let appGroupID = "group.com.osuritz.hubber"

// MARK: - WidgetSnapshotStore

/// Atomic JSON read/write for the widget's shared snapshot.
///
/// Use the injected `init(containerURL:)` in unit tests to avoid the real App Group
/// container, which requires signing. Use `init?()` in the app and widget.
public final class WidgetSnapshotStore: Sendable {
    private let fileURL: URL

    /// Designated initialiser for testing: point at any writable directory.
    public init(containerURL: URL) {
        fileURL = containerURL.appendingPathComponent("snapshot.json")
    }

    /// Convenience initialiser backed by the real App Group container.
    /// Returns `nil` when the container is unavailable (unsigned build / wrong entitlements).
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
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }

    // MARK: - Read

    /// Returns the stored snapshot, or `nil` if absent, corrupt, or unreadable.
    /// Never throws — corrupt data is treated the same as absent.
    public func read() -> WidgetSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

import Foundation

// MARK: - SnapshotStore

/// Persists and loads `ReviewSnapshot` as JSON in Application Support/Hubber/.
/// Mirror of `GitHubDevelopmentFileTokenStore` for path resolution.
final class SnapshotStore: Sendable {
    private let snapshotURL: URL

    init(snapshotURL: URL = SnapshotStore.defaultSnapshotURL) {
        self.snapshotURL = snapshotURL
    }

    convenience init(connectionID: ConnectionID) {
        self.init(snapshotURL: Self.snapshotURL(for: connectionID))
    }

    /// Loads the persisted snapshot, or returns `nil` if none exists yet.
    func load() -> ReviewSnapshot? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(ReviewSnapshot.self, from: data)
    }

    /// Persists the snapshot atomically to disk.
    func save(_ snapshot: ReviewSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: snapshotURL, options: [.atomic])
    }

    /// Removes the persisted snapshot if it exists.
    func delete() {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return }
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    // MARK: - Default path

    static var defaultSnapshotURL: URL {
        legacySnapshotURL
    }

    static var legacySnapshotURL: URL {
        hubberApplicationSupportDirectory
            .appendingPathComponent("notification-snapshot.json")
    }

    static func snapshotURL(for connectionID: ConnectionID) -> URL {
        snapshotURL(for: connectionID, in: hubberApplicationSupportDirectory)
    }

    static func snapshotURL(for connectionID: ConnectionID, in baseDirectory: URL) -> URL {
        baseDirectory
            .appendingPathComponent("notification-snapshot-\(connectionID.slug).json")
    }

    static func migrateLegacySnapshot(to connectionID: ConnectionID) {
        migrateLegacySnapshot(
            to: connectionID,
            legacyURL: legacySnapshotURL,
            newURL: snapshotURL(for: connectionID)
        )
    }

    static func migrateLegacySnapshot(to _: ConnectionID, legacyURL: URL, newURL: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: newURL.path) else { return }
        guard fileManager.fileExists(atPath: legacyURL.path) else { return }

        try? fileManager.createDirectory(
            at: newURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? fileManager.moveItem(at: legacyURL, to: newURL)
    }

    private static var hubberApplicationSupportDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let base = appSupport
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Hubber", isDirectory: true)
    }
}

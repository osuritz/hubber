import Foundation

// MARK: - SnapshotStore

/// Persists and loads `ReviewSnapshot` as JSON in Application Support/Hubber/.
/// Mirror of `GitHubDevelopmentFileTokenStore` for path resolution.
final class SnapshotStore: Sendable {
    private let snapshotURL: URL

    init(snapshotURL: URL = SnapshotStore.defaultSnapshotURL) {
        self.snapshotURL = snapshotURL
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

    // MARK: - Default path

    static var defaultSnapshotURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        let base = appSupport
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Hubber", isDirectory: true)
            .appendingPathComponent("notification-snapshot.json")
    }
}

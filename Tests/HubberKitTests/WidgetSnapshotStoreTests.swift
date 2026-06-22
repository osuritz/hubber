import Foundation
import XCTest
@testable import HubberKit

final class WidgetSnapshotStoreTests: XCTestCase {

    // MARK: - Setup

    private var tempDir: URL!
    private var sut: WidgetSnapshotStore!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotStoreTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        sut = WidgetSnapshotStore(containerURL: tempDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Fixtures

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeSnapshot(isSignedIn: Bool = true) -> WidgetSnapshot {
        WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: isSignedIn),
            connections: [ConnectionSummary(id: "conn-1", displayName: "GitHub")],
            incoming: [
                PRRowSnapshot(
                    id: "pr-99",
                    connectionID: "conn-1",
                    repo: "acme/app",
                    number: 99,
                    title: "Test PR",
                    url: URL(string: "https://github.com/acme/app/pull/99"),
                    ci: .passing,
                    review: .pending,
                    ageHours: 1.5,
                    additions: 20,
                    deletions: 5,
                    files: 3,
                    needsAttention: true
                ),
            ],
            outgoing: [],
            drafts: []
        )
    }

    // MARK: - Read when absent → nil

    func testReadWhenAbsentReturnsNil() {
        XCTAssertNil(sut.read())
    }

    // MARK: - Write → Read round-trip

    func testWriteAndReadRoundTrip() throws {
        let snapshot = makeSnapshot()
        try sut.write(snapshot)
        let loaded = sut.read()
        XCTAssertEqual(loaded, snapshot)
    }

    func testWriteOverwritesPreviousSnapshot() throws {
        let first = makeSnapshot(isSignedIn: true)
        let second = makeSnapshot(isSignedIn: false)
        try sut.write(first)
        try sut.write(second)
        let loaded = sut.read()
        XCTAssertEqual(loaded?.meta.isSignedIn, false)
    }

    // MARK: - Corrupt file → nil (no crash)

    func testCorruptFileReturnsNil() throws {
        let corruptData = Data("not valid json at all {{{".utf8)
        let fileURL = tempDir.appendingPathComponent("snapshot.json")
        try corruptData.write(to: fileURL)
        XCTAssertNil(sut.read())
    }

    // MARK: - Schema version preserved

    func testSchemaVersionIsPreservedInStoreRoundTrip() throws {
        let snapshot = makeSnapshot()
        try sut.write(snapshot)
        let loaded = sut.read()
        XCTAssertEqual(loaded?.schemaVersion, currentSchemaVersion)
    }

    // MARK: - File is written atomically (file exists after write)

    func testFileExistsAfterWrite() throws {
        let snapshot = makeSnapshot()
        try sut.write(snapshot)
        let fileURL = tempDir.appendingPathComponent("snapshot.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Two stores at different dirs are independent

    func testTwoStoresAtDifferentDirectoriesAreIndependent() throws {
        let tempDir2 = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetSnapshotStoreTests-B-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir2, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir2) }

        let storeB = WidgetSnapshotStore(containerURL: tempDir2)
        let snapshotA = makeSnapshot(isSignedIn: true)
        let snapshotB = makeSnapshot(isSignedIn: false)
        try sut.write(snapshotA)
        try storeB.write(snapshotB)

        XCTAssertEqual(sut.read()?.meta.isSignedIn, true)
        XCTAssertEqual(storeB.read()?.meta.isSignedIn, false)
    }
}

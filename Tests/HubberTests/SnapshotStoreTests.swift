import Foundation
import XCTest
@testable import Hubber

@MainActor
final class SnapshotStoreTests: XCTestCase {
    private var tempDir: URL!
    private var snapshotURL: URL!
    private var sut: SnapshotStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotStoreTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        snapshotURL = tempDir.appendingPathComponent("notification-snapshot.json")
        sut = SnapshotStore(snapshotURL: snapshotURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - load when absent → nil

    func testLoadWhenAbsentReturnsNil() {
        XCTAssertNil(sut.load())
    }

    // MARK: - save → load round-trip

    func testSaveAndLoadRoundTrip() throws {
        let snapshot = ReviewSnapshot(
            incomingIDs: ["pr-1", "pr-2"],
            outgoing: [
                "pr-42": OutgoingSnapshot(
                    reviewerStates: ["alice": "approved", "bob": "pending"],
                    ci: "passing",
                    mergeable: true,
                    approved: true
                ),
            ]
        )
        try sut.save(snapshot)
        let loaded = sut.load()
        XCTAssertEqual(loaded, snapshot)
    }

    func testSaveOverwritesPreviousSnapshot() throws {
        let first = ReviewSnapshot(incomingIDs: ["pr-1"], outgoing: [:])
        let second = ReviewSnapshot(incomingIDs: ["pr-2"], outgoing: [:])
        try sut.save(first)
        try sut.save(second)
        let loaded = sut.load()
        XCTAssertEqual(loaded, second)
    }

    // MARK: - Relaunch baseline: same data → no events

    func testPersistedBaselineMeansRelaunchProducesNoEvents() throws {
        // Simulate a previous run that saved the snapshot
        let incomingReview = makeIncomingFixture(id: "pr-1")
        let outgoingReview = makeOutgoingFixture(id: "pr-42")
        let data = HubberData(incoming: [incomingReview], outgoing: [outgoingReview], drafts: [])

        let snapshot = NotificationDiffer.snapshot(from: data)
        try sut.save(snapshot)

        // Simulate a relaunch: load the persisted baseline
        let loaded = sut.load()

        // Diff with identical data → no events
        let events = NotificationDiffer.events(
            previous: loaded,
            current: data,
            enabled: Set(NotificationEventType.allCases)
        )
        XCTAssertTrue(events.isEmpty, "Relaunch with identical data must produce no events")
    }

    // MARK: - Helpers

    private func makeIncomingFixture(id: String) -> IncomingReview {
        IncomingReview(
            id: id,
            repo: "acme/web",
            number: 1,
            title: "Fix bug",
            url: URL(string: "https://github.com/acme/web/pull/1"),
            author: GitHubUser(login: "alice", initials: "AL", color: .red),
            sloClockStart: Date(),
            additions: 5,
            deletions: 1,
            files: 1
        )
    }

    private func makeOutgoingFixture(id: String) -> OutgoingReview {
        OutgoingReview(
            id: id,
            repo: "acme/api",
            number: 42,
            title: "Add endpoint",
            url: URL(string: "https://github.com/acme/api/pull/42"),
            ci: .passing,
            ciDetail: "",
            unresolved: 0,
            approvals: 1,
            requiredApprovals: 1,
            reviewers: [Reviewer(user: GitHubUser(login: "bob", initials: "BO", color: .blue), state: .approved)],
            updatedAgoHours: 2,
            mergeable: true
        )
    }
}

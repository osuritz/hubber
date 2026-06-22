import Foundation
import XCTest
@testable import HubberKit

final class WidgetSnapshotHelpersTests: XCTestCase {

    // MARK: - Fixtures

    private func makeRow(
        id: String,
        needsAttention: Bool = false,
        ageHours: Double = 1,
        additions: Int = 0,
        deletions: Int = 0
    ) -> PRRowSnapshot {
        PRRowSnapshot(
            id: id,
            connectionID: "conn",
            repo: "acme/app",
            number: 1,
            title: "PR \(id)",
            url: nil,
            ci: .pending,
            review: .none,
            ageHours: ageHours,
            additions: additions,
            deletions: deletions,
            files: 0,
            needsAttention: needsAttention
        )
    }

    // MARK: - needsAttentionOnly

    func testNeedsAttentionOnlyFiltersCorrectly() {
        let rows = [
            makeRow(id: "a", needsAttention: true),
            makeRow(id: "b", needsAttention: false),
            makeRow(id: "c", needsAttention: true),
        ]
        let result = needsAttentionOnly(rows)
        XCTAssertEqual(result.map(\.id), ["a", "c"])
    }

    func testNeedsAttentionOnlyOnEmptyArrayReturnsEmpty() {
        XCTAssertEqual(needsAttentionOnly([]).count, 0)
    }

    func testNeedsAttentionOnlyWhenNoneNeedAttentionReturnsEmpty() {
        let rows = [makeRow(id: "a"), makeRow(id: "b")]
        XCTAssertEqual(needsAttentionOnly(rows).count, 0)
    }

    func testNeedsAttentionOnlyWhenAllNeedAttentionReturnsAll() {
        let rows = [makeRow(id: "a", needsAttention: true), makeRow(id: "b", needsAttention: true)]
        XCTAssertEqual(needsAttentionOnly(rows).count, 2)
    }

    // MARK: - sorted by urgency (oldest first)

    func testSortedUrgencyPutsOldestFirst() {
        let rows = [
            makeRow(id: "new", ageHours: 1),
            makeRow(id: "old", ageHours: 10),
            makeRow(id: "mid", ageHours: 5),
        ]
        let result = sorted(rows, by: .urgency)
        XCTAssertEqual(result.map(\.id), ["old", "mid", "new"])
    }

    func testSortedUrgencyTiesBreakByID() {
        let rows = [
            makeRow(id: "z", ageHours: 5),
            makeRow(id: "a", ageHours: 5),
        ]
        let result = sorted(rows, by: .urgency)
        XCTAssertEqual(result.map(\.id), ["a", "z"])
    }

    // MARK: - sorted by recentlyUpdated (smallest ageHours first)

    func testSortedRecentlyUpdatedPutsNewestFirst() {
        let rows = [
            makeRow(id: "old", ageHours: 10),
            makeRow(id: "new", ageHours: 0.5),
            makeRow(id: "mid", ageHours: 3),
        ]
        let result = sorted(rows, by: .recentlyUpdated)
        XCTAssertEqual(result.map(\.id), ["new", "mid", "old"])
    }

    func testSortedRecentlyUpdatedTiesBreakByID() {
        let rows = [
            makeRow(id: "z", ageHours: 2),
            makeRow(id: "a", ageHours: 2),
        ]
        let result = sorted(rows, by: .recentlyUpdated)
        XCTAssertEqual(result.map(\.id), ["a", "z"])
    }

    // MARK: - sorted by size (additions + deletions, largest first)

    func testSortedSizePutsLargestFirst() {
        let rows = [
            makeRow(id: "small", additions: 5, deletions: 2),
            makeRow(id: "large", additions: 100, deletions: 50),
            makeRow(id: "mid", additions: 20, deletions: 10),
        ]
        let result = sorted(rows, by: .size)
        XCTAssertEqual(result.map(\.id), ["large", "mid", "small"])
    }

    func testSortedSizeTiesBreakByID() {
        let rows = [
            makeRow(id: "z", additions: 10, deletions: 5),
            makeRow(id: "a", additions: 10, deletions: 5),
        ]
        let result = sorted(rows, by: .size)
        XCTAssertEqual(result.map(\.id), ["a", "z"])
    }

    func testSortedEmptyArrayReturnsEmpty() {
        XCTAssertEqual(sorted([], by: .urgency).count, 0)
        XCTAssertEqual(sorted([], by: .recentlyUpdated).count, 0)
        XCTAssertEqual(sorted([], by: .size).count, 0)
    }

    // MARK: - SnapshotMeta.isStale

    func testIsStaleReturnsTrueWhenThresholdExceeded() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-3600) // 1 hour ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        XCTAssertTrue(meta.isStale(asOf: now, threshold: 1800)) // 30 min threshold
    }

    func testIsStaleReturnsFalseWhenWithinThreshold() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-600) // 10 min ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        XCTAssertFalse(meta.isStale(asOf: now, threshold: 1800)) // 30 min threshold
    }

    func testIsStaleReturnsFalseWhenExactlyAtThreshold() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-1800) // exactly 30 min ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        // > threshold, not >=, so exactly at threshold is NOT stale
        XCTAssertFalse(meta.isStale(asOf: now, threshold: 1800))
    }

    func testIsStaleReturnsTrueOneSecondPastThreshold() {
        let now = Date()
        let lastUpdated = now.addingTimeInterval(-1801) // 30 min + 1 sec ago
        let meta = SnapshotMeta(lastUpdated: lastUpdated, isSignedIn: true)
        XCTAssertTrue(meta.isStale(asOf: now, threshold: 1800))
    }
}

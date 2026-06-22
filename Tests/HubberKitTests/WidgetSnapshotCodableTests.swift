import Foundation
import XCTest
@testable import HubberKit

final class WidgetSnapshotCodableTests: XCTestCase {

    // MARK: - Fixtures

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeSnapshot(schemaVersion: Int = currentSchemaVersion) -> WidgetSnapshot {
        WidgetSnapshot(
            schemaVersion: schemaVersion,
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: true),
            connections: [ConnectionSummary(id: "github:github.com:alice", displayName: "GitHub")],
            incoming: [
                PRRowSnapshot(
                    id: "pr-1",
                    connectionID: "github:github.com:alice",
                    repo: "acme/app",
                    number: 42,
                    title: "Fix the thing",
                    url: URL(string: "https://github.com/acme/app/pull/42"),
                    ci: .passing,
                    review: .approved,
                    ageHours: 2.5,
                    additions: 10,
                    deletions: 3,
                    files: 2,
                    needsAttention: true
                ),
            ],
            outgoing: [],
            drafts: []
        )
    }

    // MARK: - Round-trip

    func testCodableRoundTrip() throws {
        let original = makeSnapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testSchemaVersionIsPreservedInRoundTrip() throws {
        let snapshot = makeSnapshot(schemaVersion: 99)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 99)
    }

    func testCurrentSchemaVersionIsOne() {
        XCTAssertEqual(currentSchemaVersion, 1)
    }

    // MARK: - CIState raw values

    func testCIStateRawValues() {
        XCTAssertEqual(CIState.passing.rawValue, "passing")
        XCTAssertEqual(CIState.failing.rawValue, "failing")
        XCTAssertEqual(CIState.running.rawValue, "running")
        XCTAssertEqual(CIState.pending.rawValue, "pending")
        XCTAssertEqual(CIState.noChecks.rawValue, "noChecks")
    }

    func testCIStateDecodesFromRawString() throws {
        let json = Data(#"{"ci": "failing"}"#.utf8)
        struct Wrapper: Decodable { let ci: CIState }
        let decoded = try JSONDecoder().decode(Wrapper.self, from: json)
        XCTAssertEqual(decoded.ci, .failing)
    }

    // MARK: - ReviewSummary raw values

    func testReviewSummaryRawValues() {
        XCTAssertEqual(ReviewSummary.approved.rawValue, "approved")
        XCTAssertEqual(ReviewSummary.changesRequested.rawValue, "changesRequested")
        XCTAssertEqual(ReviewSummary.commented.rawValue, "commented")
        XCTAssertEqual(ReviewSummary.pending.rawValue, "pending")
        XCTAssertEqual(ReviewSummary.none.rawValue, "none")
    }

    // MARK: - Nil URL round-trips as absent

    func testNilURLRoundTrips() throws {
        let row = PRRowSnapshot(
            id: "pr-2",
            connectionID: "c",
            repo: "acme/api",
            number: 1,
            title: "Draft",
            url: nil,
            ci: .pending,
            review: .none,
            ageHours: 0,
            additions: 0,
            deletions: 0,
            files: 0,
            needsAttention: false
        )
        let snapshot = WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: false),
            connections: [],
            incoming: [row],
            outgoing: [],
            drafts: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertNil(decoded.incoming.first?.url)
    }

    // MARK: - Signed-out meta

    func testSignedOutMetaRoundTrips() throws {
        let snapshot = WidgetSnapshot(
            meta: SnapshotMeta(lastUpdated: fixedDate, isSignedIn: false),
            connections: [],
            incoming: [],
            outgoing: [],
            drafts: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertFalse(decoded.meta.isSignedIn)
    }
}

import Foundation
import HubberKit
import XCTest
@testable import Hubber

// MARK: - Helpers

private struct WidgetTestNullTelemetry: TelemetrySink {
    func send(_: String, _: [String: String]) {}
}

private struct WidgetTestIdleProvider: MachineIdleProviding {
    let isIdle = false
}

/// A `GitHubDeviceFlowServicing` stub used by tests that don't exercise auth.
private final class WidgetTestAuthService: GitHubDeviceFlowServicing, @unchecked Sendable {
    let login: String
    init(login: String) {
        self.login = login
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        throw CodeHostAuthError.badCredentials
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> StoredToken {
        throw CodeHostAuthError.badCredentials
    }

    func refresh(_ token: StoredToken) async throws -> StoredToken {
        token
    }

    func fetchAuthenticatedUser(accessToken _: String) async throws -> AuthenticatedUser {
        AuthenticatedUser(login: login, name: nil, avatarUrl: nil)
    }
}

/// A `CodeHostProvider` that returns empty lists (tests don't exercise the network).
private actor WidgetTestProvider: CodeHostProvider {
    func fetchIncomingReviews(accessToken _: String, viewerLogin _: String, mode _: IncomingReviewMode)
        async throws -> [IncomingReview] {
        []
    }

    func fetchOutgoingPullRequests(
        accessToken _: String,
        viewerLogin _: String,
        unresolvedMode _: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        []
    }

    func fetchDraftPullRequests(accessToken _: String, limit _: Int) async throws -> [DraftReview] {
        []
    }
}

/// Creates a `HubberStore` with `restoreOnInit: false` so tests control state manually.
@MainActor
private func makeStore(login: String = "alice") throws -> HubberStore {
    let suite = "widget-write-path-\(UUID())"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    let token = StoredToken(
        accessToken: "test-access-token",
        accessTokenExpiresAt: nil,
        refreshToken: nil,
        refreshTokenExpiresAt: nil,
        tokenType: "bearer",
        login: login
    )
    return HubberStore(
        authService: WidgetTestAuthService(login: login),
        provider: WidgetTestProvider(),
        tokenStore: SpyTokenStore(token: token),
        settings: SettingsStore(defaults: defaults),
        telemetry: Telemetry(sink: WidgetTestNullTelemetry()),
        snapshotStore: SnapshotStore(snapshotURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-test-snapshot-\(UUID()).json")),
        defaults: defaults,
        restoreOnInit: false
    )
}

/// Adds a connection with injected state to `hubberStore` and returns the `Connection` for
/// further mutation (e.g. setting `authState` and `data`).
@MainActor
private func addConnection(
    login: String,
    to hubberStore: HubberStore
) throws -> Connection {
    let token = StoredToken(
        accessToken: "access-\(login)",
        accessTokenExpiresAt: nil,
        refreshToken: nil,
        refreshTokenExpiresAt: nil,
        tokenType: "bearer",
        login: login
    )
    return try hubberStore.addConnection(
        id: .gitHubDotCom(login: login),
        provider: WidgetTestProvider(),
        authService: WidgetTestAuthService(login: login),
        tokenStore: SpyTokenStore(token: token),
        snapshotStore: SnapshotStore(snapshotURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("widget-conn-snap-\(UUID()).json"))
    )
}

/// Creates a temp-dir–backed `WidgetSnapshotStore` for injection in tests.
private func makeTempStore() throws -> (WidgetSnapshotStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("widget-write-path-test-\(UUID())", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return (WidgetSnapshotStore(containerURL: dir), dir)
}

// MARK: - Shared fixtures

private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func makeIncomingReview(id: String = "pr-in-1") -> IncomingReview {
    IncomingReview(
        id: id,
        repo: "acme/app",
        number: 1,
        title: "Review me",
        url: URL(string: "https://github.com/acme/app/pull/1"),
        author: CodeHostUser(login: "bob", initials: "BO", color: .gray),
        sloClockStart: fixedDate,
        additions: 5,
        deletions: 2,
        files: 1
    )
}

private func makeOutgoingReview(id: String = "pr-out-1", ci: PullRequestCI = .failing) -> OutgoingReview {
    OutgoingReview(
        id: id,
        repo: "acme/api",
        number: 2,
        title: "My PR",
        url: URL(string: "https://github.com/acme/api/pull/2"),
        ci: ci,
        ciDetail: ci.rawValue,
        unresolved: 0,
        approvals: 0,
        requiredApprovals: 1,
        reviewers: [],
        updatedAgoHours: 3.0,
        mergeable: true,
        additions: 40,
        deletions: 10,
        files: 4
    )
}

// MARK: - Tests

@MainActor
final class HubberStoreWidgetWritePathTests: XCTestCase {

    // MARK: - No-op when container is unavailable

    func testWriteWidgetSnapshotIsNoOpWhenStoreIsNil() throws {
        // appGroupWidgetStore is nil in tests (no App Group container).
        // Passing store: nil should no-op, not crash.
        let hubberStore = try makeStore()
        // The production call falls through to Self.appGroupWidgetStore, which is nil in tests.
        // We call with no injected store to confirm no crash.
        hubberStore.writeWidgetSnapshot(now: fixedDate)
    }

    func testWriteSignedOutWidgetSnapshotIsNoOpWhenStoreIsNil() throws {
        let hubberStore = try makeStore()
        hubberStore.writeSignedOutWidgetSnapshot(now: fixedDate)
    }

    // MARK: - isSignedIn reflects connection auth state

    func testIsSignedInTrueWhenConnectionIsSignedIn() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedIn(login: "alice")

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertTrue(snapshot.meta.isSignedIn)
    }

    func testIsSignedInFalseWhenConnectionIsSignedOut() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedOut

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertFalse(snapshot.meta.isSignedIn)
    }

    func testIsSignedInTrueWhenAtLeastOneConnectionIsSignedIn() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let connA = try addConnection(login: "alice", to: hubberStore)
        connA.authState = .signedIn(login: "alice")
        let connB = try addConnection(login: "bob", to: hubberStore)
        connB.authState = .signedOut

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertTrue(snapshot.meta.isSignedIn)
    }

    // MARK: - lastUpdated is the injected date

    func testLastUpdatedMatchesInjectedDate() throws {
        let hubberStore = try makeStore()
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        // Date round-trips via ISO8601 — allow 1-second tolerance for encoding precision.
        XCTAssertEqual(
            snapshot.meta.lastUpdated.timeIntervalSince1970,
            fixedDate.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    // MARK: - Connection list and connectionID attribution

    func testConnectionListIsPopulatedWithConnID() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let connID = ConnectionID.gitHubDotCom(login: "alice")
        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedIn(login: "alice")

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.connections.count, 1)
        XCTAssertEqual(snapshot.connections[0].id, connID.description)
        XCTAssertEqual(snapshot.connections[0].displayName, "GitHub · @alice")
    }

    func testRowsTaggedWithOwningConnectionID() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let connID = ConnectionID.gitHubDotCom(login: "alice")
        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedIn(login: "alice")
        conn.replaceData(HubberData(incoming: [makeIncomingReview()], outgoing: [], drafts: []))

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.incoming.count, 1)
        XCTAssertEqual(snapshot.incoming[0].connectionID, connID.description)
    }

    func testMultiConnectionDuplicateRowIsDeduplicatedFirstConnectionWins() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sharedPR = makeIncomingReview(id: "shared-pr-1")
        let connA = try addConnection(login: "alice", to: hubberStore)
        connA.authState = .signedIn(login: "alice")
        connA.replaceData(HubberData(incoming: [sharedPR], outgoing: [], drafts: []))

        let connB = try addConnection(login: "bob", to: hubberStore)
        connB.authState = .signedIn(login: "bob")
        connB.replaceData(HubberData(incoming: [sharedPR], outgoing: [], drafts: []))

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        // Duplicate id de-duplicated: only one row
        XCTAssertEqual(snapshot.incoming.count, 1)
        // Attribution: first connection (alice) wins
        XCTAssertEqual(snapshot.incoming[0].connectionID, ConnectionID.gitHubDotCom(login: "alice").description)
    }

    func testMultiConnectionDistinctRowsBothPresent() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let connA = try addConnection(login: "alice", to: hubberStore)
        connA.authState = .signedIn(login: "alice")
        connA.replaceData(HubberData(incoming: [makeIncomingReview(id: "pr-a")], outgoing: [], drafts: []))

        let connB = try addConnection(login: "bob", to: hubberStore)
        connB.authState = .signedIn(login: "bob")
        connB.replaceData(HubberData(incoming: [makeIncomingReview(id: "pr-b")], outgoing: [], drafts: []))

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.incoming.count, 2)
        let ids = Set(snapshot.incoming.map(\.id))
        XCTAssertEqual(ids, ["pr-a", "pr-b"])
    }

    // MARK: - Partial-failure preservation

    /// Verifies the spec's partial-failure guarantee: the snapshot write-path faithfully
    /// reflects `Connection.data` as-is. `Connection.fetchAllTabsIndependently` → `resolveTab`
    /// returns the *existing* data when a tab fetch fails, so `Connection.data` is never
    /// collapsed to empty on a partial failure. The write-path does not add extra collapsing.
    func testPartialFailureLastKnownRowsReflectedInSnapshot() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Simulate a connection whose last fetch left known incoming rows (as if a tab refresh
        // failed and `resolveTab` returned the existing data, not []).
        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedIn(login: "alice")
        conn.replaceData(HubberData(incoming: [makeIncomingReview(id: "last-known-pr")], outgoing: [], drafts: []))

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        // Last-known row is present — not collapsed to empty.
        XCTAssertEqual(snapshot.incoming.count, 1)
        XCTAssertEqual(snapshot.incoming[0].id, "last-known-pr")
    }

    // MARK: - needsAttention mapping

    func testOutgoingWithFailingCINeedsAttentionInSnapshot() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedIn(login: "alice")
        conn.replaceData(HubberData(incoming: [], outgoing: [makeOutgoingReview(ci: .failing)], drafts: []))

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.outgoing.count, 1)
        XCTAssertTrue(snapshot.outgoing[0].needsAttention)
    }

    func testOutgoingWithPassingCIIsNotNeedsAttentionInSnapshot() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedIn(login: "alice")
        conn.replaceData(HubberData(incoming: [], outgoing: [makeOutgoingReview(ci: .passing)], drafts: []))

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.outgoing.count, 1)
        XCTAssertFalse(snapshot.outgoing[0].needsAttention)
    }

    // MARK: - Sign-out snapshot

    func testWriteSignedOutSnapshotHasEmptySignedOutMeta() throws {
        let hubberStore = try makeStore()
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        hubberStore.writeSignedOutWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertFalse(snapshot.meta.isSignedIn)
        XCTAssertTrue(snapshot.connections.isEmpty)
        XCTAssertTrue(snapshot.incoming.isEmpty)
        XCTAssertTrue(snapshot.outgoing.isEmpty)
        XCTAssertTrue(snapshot.drafts.isEmpty)
    }

    func testWriteSignedOutSnapshotLastUpdatedMatchesDate() throws {
        let hubberStore = try makeStore()
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        hubberStore.writeSignedOutWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(
            snapshot.meta.lastUpdated.timeIntervalSince1970,
            fixedDate.timeIntervalSince1970,
            accuracy: 1.0
        )
    }

    func testWriteSignedOutSnapshotOverwritesPreviousData() throws {
        let hubberStore = try makeStore(login: "alice")
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Write a snapshot with data first
        let conn = try addConnection(login: "alice", to: hubberStore)
        conn.authState = .signedIn(login: "alice")
        conn.replaceData(HubberData(incoming: [makeIncomingReview()], outgoing: [], drafts: []))
        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)
        XCTAssertFalse(store.read()?.incoming.isEmpty ?? true, "Precondition: data snapshot was written")

        // Sign-out snapshot should clear everything
        hubberStore.writeSignedOutWidgetSnapshot(to: store, now: fixedDate)

        let signed = try XCTUnwrap(store.read())
        XCTAssertFalse(signed.meta.isSignedIn)
        XCTAssertTrue(signed.incoming.isEmpty)
    }

    // MARK: - Schema version

    func testWrittenSnapshotHasCurrentSchemaVersion() throws {
        let hubberStore = try makeStore()
        let (store, dir) = try makeTempStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        hubberStore.writeWidgetSnapshot(to: store, now: fixedDate)

        let snapshot = try XCTUnwrap(store.read())
        XCTAssertEqual(snapshot.schemaVersion, currentSchemaVersion)
    }

    // MARK: - HubberWidgetKind constant

    func testWidgetKindConstantMatchesExpectedBundleID() {
        // Both host and widget must agree on this string. If it changes, this test breaks
        // before the widget stops working — acting as a canary for accidental renames.
        XCTAssertEqual(HubberWidgetKind.prList, "com.osuritz.hubber.widget")
    }
}

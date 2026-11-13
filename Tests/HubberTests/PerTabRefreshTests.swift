import Foundation
import XCTest
@testable import Hubber

// MARK: - Stub provider

/// A `CodeHostProvider` whose per-method responses are configurable at construction time.
///
/// Each method either returns a canned result or throws a canned error.
/// This lets tests simulate exactly one tab failing while the others succeed.
private actor StubCodeHostProvider: CodeHostProvider {
    let incomingResult: Result<[IncomingReview], Error>
    let outgoingResult: Result<[OutgoingReview], Error>
    let draftsResult: Result<[DraftReview], Error>

    init(
        incoming: Result<[IncomingReview], Error>,
        outgoing: Result<[OutgoingReview], Error>,
        drafts: Result<[DraftReview], Error>
    ) {
        incomingResult = incoming
        outgoingResult = outgoing
        draftsResult = drafts
    }

    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        try incomingResult.get()
    }

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        try outgoingResult.get()
    }

    func fetchDraftPullRequests(
        accessToken: String,
        limit: Int
    ) async throws -> [DraftReview] {
        try draftsResult.get()
    }
}

// MARK: - Helpers

private enum TestError: Error, LocalizedError {
    case networkFailure

    var errorDescription: String? {
        "Network failure"
    }
}

/// Returns a `HubberStore` pre-signed-in with a given stub provider.
/// Uses the `SpyTokenStore` from `HubberStoreRestoreSessionTests.swift`
/// (already in the test target).
@MainActor
private func makeSignedInStore(provider: some CodeHostProvider) -> HubberStore {
    let token = StoredToken(
        accessToken: "test-token",
        accessTokenExpiresAt: nil,
        refreshToken: nil,
        refreshTokenExpiresAt: nil,
        tokenType: "bearer",
        login: "testuser"
    )
    let tokenStore = SpyTokenStore(token: token)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    // Return 200 for /user so restoreSession succeeds (resolves to signedIn)
    MockURLProtocol.handler = { _ in
        guard
            let url = URL(string: "https://api.github.com/user"),
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)
        else {
            throw URLError(.badURL)
        }
        let body = try JSONSerialization.data(withJSONObject: ["login": "testuser"])
        return (response, body)
    }
    let authService = GitHubAuthService(clientID: "test", session: URLSession(configuration: config))
    return HubberStore(
        authService: authService,
        provider: provider,
        tokenStore: tokenStore,
        telemetry: Telemetry(sink: NullTelemetrySink())
    )
}

/// A no-op `TelemetrySink` for tests that don't care about telemetry events.
private struct NullTelemetrySink: TelemetrySink {
    func send(_ event: String, _ params: [String: String]) {}
}

/// Waits until `authState` is `.signedIn` (or times out).
@MainActor
private func waitForSignedIn(_ store: HubberStore, timeout: TimeInterval = 3) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if case .signedIn = store.authState {
            return
        }
        try await Task.sleep(for: .milliseconds(50))
    }
    // If still not signedIn after timeout, the test helper fails gracefully
}

// MARK: - Shared test data

/// Non-empty incoming reviews used across tests so "tab populated" assertions are non-vacuous.
private let sampleIncoming = [
    IncomingReview(
        id: "pr-1",
        repo: "org/repo",
        number: 1,
        title: "PR title",
        url: nil,
        author: .marisol,
        sloClockStart: .hoursAgo(1),
        additions: 10,
        deletions: 5,
        files: 2
    ),
]

/// Non-empty outgoing reviews used across tests so "tab populated" assertions are non-vacuous.
private let sampleOutgoingNonEmpty = [
    OutgoingReview(
        id: "pr-3",
        repo: "org/repo",
        number: 3,
        title: "Outgoing PR",
        url: nil,
        ci: .passing,
        ciDetail: "",
        unresolved: 0,
        approvals: 1,
        requiredApprovals: 1,
        reviewers: [],
        updatedAgoHours: 1,
        mergeable: true
    ),
]

/// Non-empty drafts used across tests so "tab populated" assertions are non-vacuous.
private let sampleDrafts = [
    DraftReview(
        id: "pr-2",
        repo: "org/repo",
        number: 2,
        title: "Draft title",
        url: nil,
        ci: .pending,
        ciDetail: "",
        commits: 1,
        updatedAt: .hoursAgo(0.5)
    ),
]

// MARK: - Tests

@MainActor
final class PerTabRefreshTests: XCTestCase {

    /// When the outgoing tab throws but incoming and drafts succeed, the two successful
    /// tabs must be populated (non-empty) and only the failing tab must carry an error.
    func testOutgoingFailureKeepsIncomingAndDraftsPopulated() async throws {
        let provider = StubCodeHostProvider(
            incoming: .success(sampleIncoming),
            outgoing: .failure(TestError.networkFailure),
            drafts: .success(sampleDrafts)
        )

        let store = makeSignedInStore(provider: provider)
        try await waitForSignedIn(store)

        // Trigger a refresh and wait for it to complete
        store.refreshPullRequests()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !store.isRefreshingPullRequests {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        // Incoming populated (non-empty — assertion is non-vacuous)
        XCTAssertEqual(store.data.incoming.count, 1, "Incoming should be populated despite outgoing failure")
        // Drafts populated (non-empty — assertion is non-vacuous)
        XCTAssertEqual(store.data.drafts.count, 1, "Drafts should be populated despite outgoing failure")
        // Outgoing: existing data kept (HubberData.sample has outgoing; may or may not be empty)
        // The key assertion is that the per-tab error is set.
        XCTAssertNil(store.incomingError, "Incoming tab should have no error")
        XCTAssertNotNil(store.outgoingError, "Outgoing tab should have an error")
        XCTAssertNil(store.draftsError, "Drafts tab should have no error")
    }

    /// When one tab returns a global rate-limit error while the other two succeed,
    /// the two successful tabs' data IS committed (non-empty) and the global rate-limit
    /// handling is applied (rateLimitedUntil is set or rateLimitMessage is non-nil).
    ///
    /// This test exercises the previously-buggy global-error branch where early-return
    /// before the `data = HubberData(...)` assignment would discard successful tab data.
    func testRateLimitedTabCommitsSuccessfulTabsAndSetsBackoff() async throws {
        let retryAfter: TimeInterval = 5 * 60
        let provider = StubCodeHostProvider(
            incoming: .success(sampleIncoming), // success — non-empty
            outgoing: .failure(CodeHostAuthError.rateLimited(retryAfter: retryAfter)), // global error
            drafts: .success(sampleDrafts) // success — non-empty
        )

        let store = makeSignedInStore(provider: provider)
        try await waitForSignedIn(store)

        store.refreshPullRequests()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !store.isRefreshingPullRequests {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        // Both successful tabs must be committed (non-empty proves the assertion is non-vacuous).
        XCTAssertGreaterThan(
            store.data.incoming.count,
            0,
            "Incoming data must be committed even when another tab hits a global rate-limit error"
        )
        XCTAssertGreaterThan(
            store.data.drafts.count,
            0,
            "Drafts data must be committed even when another tab hits a global rate-limit error"
        )

        // Global rate-limit handling must have been applied.
        XCTAssertNotNil(
            store.rateLimitMessage,
            "Rate-limit backoff must be applied after a rateLimited error"
        )
    }

    /// When all three tabs succeed, all tabs are populated and no per-tab error is set.
    func testAllTabsSucceedNilErrors() async throws {
        let provider = StubCodeHostProvider(
            incoming: .success([]),
            outgoing: .success([]),
            drafts: .success([])
        )

        let store = makeSignedInStore(provider: provider)
        try await waitForSignedIn(store)

        store.refreshPullRequests()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !store.isRefreshingPullRequests {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertNil(store.incomingError, "No error when incoming succeeds")
        XCTAssertNil(store.outgoingError, "No error when outgoing succeeds")
        XCTAssertNil(store.draftsError, "No error when drafts succeeds")
        // Legacy pullRequestRefreshError should also be nil
        XCTAssertNil(store.pullRequestRefreshError)
    }

    /// When only the incoming tab fails, outgoing (non-empty) and drafts remain populated.
    func testIncomingFailureKeepsOtherTabsPopulated() async throws {
        let provider = StubCodeHostProvider(
            incoming: .failure(TestError.networkFailure),
            outgoing: .success(sampleOutgoingNonEmpty),
            drafts: .success(sampleDrafts)
        )

        let store = makeSignedInStore(provider: provider)
        try await waitForSignedIn(store)

        store.refreshPullRequests()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if !store.isRefreshingPullRequests {
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        XCTAssertEqual(store.data.outgoing.count, 1, "Outgoing should be populated (non-empty) when incoming fails")
        XCTAssertEqual(store.data.drafts.count, 1, "Drafts should be populated (non-empty) when incoming fails")
        XCTAssertNotNil(store.incomingError, "Incoming tab should carry an error")
        XCTAssertNil(store.outgoingError, "Outgoing tab should have no error")
        XCTAssertNil(store.draftsError, "Drafts tab should have no error")
    }
}

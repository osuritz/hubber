import Foundation
import XCTest
@testable import Hubber

// MARK: - Thread-safe test clock

/// A thread-safe clock for testing. Single-threaded tests mutate `now` between awaits.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    var now: Date {
        get { lock.withLock { _now } }
        set { lock.withLock { _now = newValue } }
    }

    init(now: Date = Date()) {
        _now = now
    }
}

// MARK: - Spy provider

actor SpyProvider: CodeHostProvider {
    private(set) var incomingCallCount = 0
    private(set) var outgoingCallCount = 0
    private(set) var draftsCallCount = 0

    var nextError: Error?

    func setNextError(_ error: Error?) {
        nextError = error
    }

    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        incomingCallCount += 1
        if let error = nextError { throw error }
        return [
            IncomingReview(
                id: "IR-\(viewerLogin)-\(mode.rawValue)",
                repo: "acme/ios",
                number: 1,
                title: "Incoming PR",
                url: nil,
                author: CodeHostUser(login: "alice", initials: "AL", color: .white),
                sloClockStart: Date(),
                additions: 0,
                deletions: 0,
                files: 0
            ),
        ]
    }

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        outgoingCallCount += 1
        if let error = nextError { throw error }
        return [
            OutgoingReview(
                id: "OR-\(viewerLogin)-\(unresolvedMode.rawValue)",
                repo: "acme/ios",
                number: 2,
                title: "Outgoing PR",
                url: nil,
                ci: .passing,
                ciDetail: "1/1",
                unresolved: 0,
                approvals: 1,
                requiredApprovals: 1,
                reviewers: [],
                updatedAgoHours: 0,
                mergeable: true
            ),
        ]
    }

    func fetchDraftPullRequests(
        accessToken: String,
        limit: Int
    ) async throws -> [DraftReview] {
        draftsCallCount += 1
        if let error = nextError { throw error }
        return [
            DraftReview(
                id: "DR-\(limit)",
                repo: "acme/ios",
                number: 3,
                title: "Draft PR",
                url: nil,
                ci: .pending,
                ciDetail: "pending",
                commits: 1,
                updatedAt: Date()
            ),
        ]
    }
}

// MARK: - Tests

final class CachingCodeHostProviderTests: XCTestCase {
    private let ttl: TimeInterval = 300 // 5 minutes

    /// a) Cache hit within TTL: spy called only once
    func testReturnsCachedResultWithinTTL() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        let first = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )
        let second = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        let callCount = await spy.incomingCallCount
        XCTAssertEqual(callCount, 1, "Spy should be called only once within TTL")
        XCTAssertEqual(first.map(\.id), second.map(\.id), "Both results should be equal")
    }

    /// b) After TTL expires, fetches again
    func testRefetchesAfterTTLExpires() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        // Advance clock past TTL
        clock.now = clock.now.addingTimeInterval(ttl + 1)

        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        let callCount = await spy.incomingCallCount
        XCTAssertEqual(callCount, 2, "Spy should be called again after TTL expires")
    }

    /// c) Different keys cache independently
    func testDistinctKeysCacheIndependently() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )
        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .team
        )

        let callCount = await spy.incomingCallCount
        XCTAssertEqual(callCount, 2, "Different modes produce different cache keys")
    }

    /// d) Errors are never cached: second call within TTL should retry
    func testErrorsAreNotCached() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        // First call: inject error
        await spy.setNextError(CodeHostAuthError.invalidResponse)
        do {
            _ = try await sut.fetchIncomingReviews(
                accessToken: "tok",
                viewerLogin: "alice",
                mode: .explicit
            )
            XCTFail("Expected error to be thrown")
        } catch {}

        // Second call within TTL: clear error, should call spy again (not return cached error)
        await spy.setNextError(nil)
        let result = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        let callCount = await spy.incomingCallCount
        XCTAssertEqual(callCount, 2, "Spy should be called again after error (errors not cached)")
        XCTAssertFalse(result.isEmpty, "Second call should succeed")
    }

    /// e) Outgoing cache hit within TTL
    func testOutgoingReturnsCachedResultWithinTTL() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        let first = try await sut.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "alice",
            unresolvedMode: .allOpen
        )
        let second = try await sut.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "alice",
            unresolvedMode: .allOpen
        )

        let callCount = await spy.outgoingCallCount
        XCTAssertEqual(callCount, 1, "Outgoing spy should be called only once within TTL")
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    /// f) Drafts cache hit within TTL
    func testDraftsReturnsCachedResultWithinTTL() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        let first = try await sut.fetchDraftPullRequests(accessToken: "tok", limit: 50)
        let second = try await sut.fetchDraftPullRequests(accessToken: "tok", limit: 50)

        let callCount = await spy.draftsCallCount
        XCTAssertEqual(callCount, 1, "Drafts spy should be called only once within TTL")
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    /// g) At exactly TTL (not TTL+1), the cache is expired because the guard is strict `< ttl`
    func testRefetchesAtExactTTLBoundary() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        // Advance clock by EXACTLY ttl — the guard `< ttl` fails, so a refetch is required
        clock.now = clock.now.addingTimeInterval(ttl)

        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        let callCount = await spy.incomingCallCount
        XCTAssertEqual(callCount, 2, "Cache guard is strict < ttl, so exactly ttl triggers a refetch")
    }

    /// h) invalidateAll forces a refetch even within TTL
    func testInvalidateAllForcesRefetch() async throws {
        let spy = SpyProvider()
        let clock = TestClock(now: Date())
        let sut = CachingCodeHostProvider(
            wrapping: spy,
            ttl: ttl,
            now: { clock.now }
        )

        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        let firstCallCount = await spy.incomingCallCount
        XCTAssertEqual(firstCallCount, 1, "Initial fetch should call spy once")

        // Invalidate all caches — clock stays within TTL
        await sut.invalidateAll()

        _ = try await sut.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "alice",
            mode: .explicit
        )

        let secondCallCount = await spy.incomingCallCount
        XCTAssertEqual(secondCallCount, 2, "After invalidateAll, spy must be called again even within TTL")
    }
}

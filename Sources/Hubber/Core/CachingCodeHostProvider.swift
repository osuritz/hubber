import Foundation

actor CachingCodeHostProvider: CodeHostProvider, CodeHostCacheInvalidating {
    private let wrapped: any CodeHostProvider
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    private var incoming: [String: (date: Date, value: [IncomingReview])] = [:]
    private var outgoing: [String: (date: Date, value: [OutgoingReview])] = [:]
    private var drafts: [String: (date: Date, value: [DraftReview])] = [:]

    init(
        wrapping provider: any CodeHostProvider,
        ttl: TimeInterval = 300,
        now: @Sendable @escaping () -> Date = { Date() }
    ) {
        wrapped = provider
        self.ttl = ttl
        self.now = now
    }

    // MARK: - CodeHostProvider

    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws -> [IncomingReview] {
        let key = "\(viewerLogin)|\(mode.rawValue)"
        if let entry = incoming[key], now().timeIntervalSince(entry.date) < ttl {
            return entry.value
        }
        let value = try await wrapped.fetchIncomingReviews(
            accessToken: accessToken,
            viewerLogin: viewerLogin,
            mode: mode
        )
        incoming[key] = (now(), value)
        return value
    }

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws -> [OutgoingReview] {
        let key = "\(viewerLogin)|\(unresolvedMode.rawValue)"
        if let entry = outgoing[key], now().timeIntervalSince(entry.date) < ttl {
            return entry.value
        }
        let value = try await wrapped.fetchOutgoingPullRequests(
            accessToken: accessToken,
            viewerLogin: viewerLogin,
            unresolvedMode: unresolvedMode
        )
        outgoing[key] = (now(), value)
        return value
    }

    func fetchDraftPullRequests(
        accessToken: String,
        limit: Int
    ) async throws -> [DraftReview] {
        let key = "\(limit)"
        if let entry = drafts[key], now().timeIntervalSince(entry.date) < ttl {
            return entry.value
        }
        let value = try await wrapped.fetchDraftPullRequests(
            accessToken: accessToken,
            limit: limit
        )
        drafts[key] = (now(), value)
        return value
    }

    // MARK: - CodeHostCacheInvalidating

    func invalidateAll() {
        incoming.removeAll()
        outgoing.removeAll()
        drafts.removeAll()
    }
}

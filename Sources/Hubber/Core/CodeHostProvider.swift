import Foundation

protocol CodeHostProvider: Sendable {
    func fetchIncomingReviews(
        accessToken: String,
        viewerLogin: String,
        mode: IncomingReviewMode
    ) async throws
        -> [IncomingReview]

    func fetchOutgoingPullRequests(
        accessToken: String,
        viewerLogin: String,
        unresolvedMode: UnresolvedThreadMode
    ) async throws
        -> [OutgoingReview]

    func fetchDraftPullRequests(
        accessToken: String,
        limit: Int
    ) async throws
        -> [DraftReview]
}

/// Adopted by providers that support evicting their in-memory cache on demand.
/// Call `invalidateAll()` on sign-out to prevent a newly-signed-in account from
/// seeing the previous user's cached data within the remaining TTL window.
protocol CodeHostCacheInvalidating: Sendable {
    func invalidateAll() async
}

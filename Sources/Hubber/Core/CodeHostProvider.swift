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

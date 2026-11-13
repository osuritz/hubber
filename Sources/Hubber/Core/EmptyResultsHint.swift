import Foundation

/// Decides whether the empty tabs should hint that missing organization access may be the cause.
enum EmptyResultsHint {
    static let helpURL = URL(
        string: "https://github.com/osuritz/hubber/blob/main/docs/token-permissions.md"
            + "#not-seeing-your-organizations-pull-requests"
    )

    /// True only when signed in, at least one refresh succeeded, no refresh is running or failing,
    /// and every list is empty.
    static func shouldShow(
        hasSignedInConnection: Bool,
        lastRefresh: Date?,
        hasRefreshError: Bool,
        isRefreshing: Bool,
        data: HubberData
    ) -> Bool {
        hasSignedInConnection
            && lastRefresh != nil
            && !hasRefreshError
            && !isRefreshing
            && data.incoming.isEmpty
            && data.outgoing.isEmpty
            && data.drafts.isEmpty
    }

    @MainActor
    static func shouldShow(store: HubberStore) -> Bool {
        let connections = store.connections
        return shouldShow(
            hasSignedInConnection: connections.contains { connection in
                if case .signedIn = connection.authState {
                    return true
                }
                return false
            },
            lastRefresh: connections.compactMap(\.lastPullRequestRefresh).max(),
            hasRefreshError: connections.contains {
                $0.pullRequestRefreshError != nil || $0.incomingError != nil
                    || $0.outgoingError != nil || $0.draftsError != nil
            },
            isRefreshing: store.isRefreshingPullRequests,
            data: store.data
        )
    }
}

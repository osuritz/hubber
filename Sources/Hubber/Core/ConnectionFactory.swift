import Foundation

/// Maps a `ConnectionID` (provider + host) to the concrete provider + auth service that target
/// that host. github.com / GitHub Enterprise → GitHub types; gitlab → GitLab types. The `baseURL`
/// is derived from the id's host, so the #82/#60 baseURL seams route to the right server.
enum ConnectionFactory {
    static func baseURL(for id: ConnectionID) -> URL {
        URL(string: "https://\(id.host)") ?? URL(string: "https://github.com")!
    }

    static func providerAndAuth(
        for id: ConnectionID,
        session: URLSession = .shared
    ) -> (provider: any CodeHostProvider, authService: any GitHubDeviceFlowServicing) {
        let url = baseURL(for: id)
        switch id.provider {
        case "gitlab":
            return (
                CachingCodeHostProvider(wrapping: GitLabProvider(baseURL: url, session: session)),
                GitLabAuthService(baseURL: url, session: session)
            )
        default:
            return (
                CachingCodeHostProvider(wrapping: GitHubProvider(baseURL: url, session: session)),
                GitHubAuthService(baseURL: url, session: session)
            )
        }
    }
}

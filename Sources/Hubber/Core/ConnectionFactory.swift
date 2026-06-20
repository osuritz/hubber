import Foundation

/// Maps a `ConnectionID` (provider + host) to the concrete provider + auth service that target
/// that host. github.com / GitHub Enterprise → GitHub types; gitlab → GitLab types. The `baseURL`
/// is derived from the id's host, so the #82/#60 baseURL seams route to the right server.
enum ConnectionFactory {
    static func baseURL(for id: ConnectionID) -> URL {
        URL(string: "https://\(id.host)") ?? URL(string: "https://github.com")!
    }

    /// Builds an auth service for a provider+host before a login is known (identity resolution
    /// during add-account). Mirrors `providerAndAuth(for:)`'s auth half.
    static func authService(
        provider: String,
        host: String,
        session: URLSession = .shared
    ) -> any CodeHostAuthServicing {
        let url = URL(string: "https://\(host)") ?? URL(string: "https://github.com")!
        switch provider.lowercased() {
        case "gitlab":
            return GitLabAuthService(baseURL: url, session: session)
        default:
            return GitHubAuthService(baseURL: url, session: session)
        }
    }

    static func providerAndAuth(
        for id: ConnectionID,
        session: URLSession = .shared
    ) -> (provider: any CodeHostProvider, authService: any CodeHostAuthServicing) {
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

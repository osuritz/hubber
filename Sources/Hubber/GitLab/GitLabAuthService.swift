import Foundation

/// GitLab authentication over a Personal Access Token. Conforms to the device-flow seam for
/// `Connection` compatibility, but GitLab has no device flow and PATs don't refresh — only
/// `fetchAuthenticatedUser` is real; the rest throw. Reuses `GitLabProvider`'s GraphQL transport.
final class GitLabAuthService: GitHubDeviceFlowServicing, Sendable {
    private let transport: GitLabProvider

    init(baseURL: URL = URL(string: "https://gitlab.com")!, session: URLSession = .shared) {
        transport = GitLabProvider(baseURL: baseURL, session: session)
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser {
        let payload = try await transport.graphQL(
            query: Self.currentUserQuery,
            variables: [:],
            accessToken: accessToken
        )
        guard
            let currentUser = payload["currentUser"] as? [String: Any],
            let username = currentUser["username"] as? String
        else { throw GitHubAuthError.invalidResponse }
        return GitHubAuthenticatedUser(
            login: username,
            name: currentUser["name"] as? String,
            avatarUrl: currentUser["avatarUrl"] as? String
        )
    }

    func refresh(_: GitHubStoredToken) async throws -> GitHubStoredToken {
        throw GitHubAuthError.missingRefreshToken
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        throw GitHubAuthError.github("GitLab does not support device sign-in; use a personal access token.")
    }

    func pollForToken(deviceAuthorization _: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        throw GitHubAuthError.github("GitLab does not support device sign-in; use a personal access token.")
    }

    private static let currentUserQuery = "query { currentUser { username name avatarUrl } }"
}

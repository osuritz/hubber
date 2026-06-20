import Foundation

/// GitLab authentication over a Personal Access Token. GitLab has no device flow, so it conforms to
/// the neutral `CodeHostAuthServicing` seam (not the GitHub device-flow protocol). PATs don't
/// refresh, so `refresh` throws; `fetchAuthenticatedUser` is the real path. Reuses `GitLabProvider`'s
/// GraphQL transport.
final class GitLabAuthService: CodeHostAuthServicing, Sendable {
    private let transport: GitLabProvider

    init(baseURL: URL = URL(string: "https://gitlab.com")!, session: URLSession = .shared) {
        transport = GitLabProvider(baseURL: baseURL, session: session)
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> AuthenticatedUser {
        let payload = try await transport.graphQL(
            query: Self.currentUserQuery,
            variables: [:],
            accessToken: accessToken
        )
        guard
            let currentUser = payload["currentUser"] as? [String: Any],
            let username = currentUser["username"] as? String
        else { throw CodeHostAuthError.invalidResponse }
        return AuthenticatedUser(
            login: username,
            name: currentUser["name"] as? String,
            avatarUrl: currentUser["avatarUrl"] as? String
        )
    }

    func refresh(_: StoredToken) async throws -> StoredToken {
        throw CodeHostAuthError.missingRefreshToken
    }

    private static let currentUserQuery = "query { currentUser { username name avatarUrl } }"
}

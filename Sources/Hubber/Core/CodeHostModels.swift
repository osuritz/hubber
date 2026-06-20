import Foundation
import Security

// Provider-neutral credential/auth value types and the neutral authentication seam, shared by
// every CodeHostProvider / auth-service implementation (GitHub and GitLab alike).

struct StoredToken: Codable, Equatable {
    var accessToken: String
    var accessTokenExpiresAt: Date?
    var refreshToken: String?
    var refreshTokenExpiresAt: Date?
    var tokenType: String
    var login: String?

    var canRefresh: Bool {
        guard let refreshToken, !refreshToken.isEmpty else { return false }
        guard let refreshTokenExpiresAt else { return true }
        return refreshTokenExpiresAt > Date().addingTimeInterval(60)
    }

    var hasFreshAccessToken: Bool {
        guard let accessTokenExpiresAt else { return true }
        return accessTokenExpiresAt > Date().addingTimeInterval(5 * 60)
    }
}

struct AuthenticatedUser: Decodable, Equatable {
    let login: String
    let name: String?
    let avatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case login
        case name
        case avatarUrl = "avatar_url"
    }
}

enum CodeHostAuthError: LocalizedError, Equatable {
    case invalidResponse
    case authorizationExpired
    case authorizationDenied
    case deviceFlowDisabled
    case badCredentials
    case missingRefreshToken
    case keychain(OSStatus)
    case providerMessage(String)
    case rateLimited(retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server returned an unexpected response."
        case .authorizationExpired:
            "The GitHub sign-in code expired. Start sign-in again."
        case .authorizationDenied:
            "GitHub sign-in was cancelled."
        case .deviceFlowDisabled:
            "Device Flow is not enabled for this GitHub App."
        case .badCredentials:
            "The server rejected the saved credentials. Please sign in again."
        case .missingRefreshToken:
            "The saved token cannot be refreshed. Please sign in again."
        case let .keychain(status):
            "Keychain returned status \(status)."
        case let .providerMessage(message):
            message
        case let .rateLimited(retryAfter):
            retryAfter.map { seconds in
                "Rate limit reached. Retry in \(Int((seconds / 60).rounded(.up)))m."
            } ?? "Rate limit reached."
        }
    }
}

/// Generic code-host authentication seam shared by all providers. GitHub refines this with
/// `GitHubDeviceFlowServicing`; GitLab (PAT-only) conforms to this base directly.
protocol CodeHostAuthServicing: Sendable {
    func refresh(_ token: StoredToken) async throws -> StoredToken
    func fetchAuthenticatedUser(accessToken: String) async throws -> AuthenticatedUser
}

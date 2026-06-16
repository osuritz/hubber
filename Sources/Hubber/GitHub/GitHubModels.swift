import Foundation
import Security

// MARK: - GitHub API types used by GitHubAuth and HubberStore

struct GitHubDeviceAuthorization: Equatable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresAt: Date
    let interval: Int

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

struct GitHubStoredToken: Codable, Equatable {
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

struct GitHubAuthenticatedUser: Decodable, Equatable {
    let login: String
    let name: String?
    let avatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case login
        case name
        case avatarUrl = "avatar_url"
    }
}

enum GitHubAuthError: LocalizedError, Equatable {
    case invalidResponse
    case authorizationExpired
    case authorizationDenied
    case deviceFlowDisabled
    case badCredentials
    case missingRefreshToken
    case keychain(OSStatus)
    case github(String)
    case rateLimited(retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned an unexpected response."
        case .authorizationExpired:
            "The GitHub sign-in code expired. Start sign-in again."
        case .authorizationDenied:
            "GitHub sign-in was cancelled."
        case .deviceFlowDisabled:
            "Device Flow is not enabled for this GitHub App."
        case .badCredentials:
            "GitHub rejected the saved credentials. Please sign in again."
        case .missingRefreshToken:
            "The saved token cannot be refreshed. Please sign in again."
        case let .keychain(status):
            "Keychain returned status \(status)."
        case let .github(message):
            message
        case let .rateLimited(retryAfter):
            retryAfter.map { seconds in
                "GitHub rate limit reached. Retry in \(Int((seconds / 60).rounded(.up)))m."
            } ?? "GitHub rate limit reached."
        }
    }
}

import Foundation

// MARK: - OAuth device-flow response types (used by GitHubAuthService)

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }
}

struct TokenResponse: Decodable {
    let accessToken: String?
    let expiresIn: Int?
    let refreshToken: String?
    let refreshTokenExpiresIn: Int?
    let tokenType: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?

    func storedToken() -> GitHubStoredToken? {
        guard let accessToken else {
            return nil
        }

        return GitHubStoredToken(
            accessToken: accessToken,
            accessTokenExpiresAt: expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            tokenType: tokenType ?? "bearer",
            login: nil
        )
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
        case tokenType = "token_type"
        case error
        case errorDescription = "error_description"
        case interval
    }
}

// MARK: - URL form encoding helpers

extension [String: String] {
    func formURLEncoded() -> String {
        map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .sorted()
        .joined(separator: "&")
    }
}

extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}

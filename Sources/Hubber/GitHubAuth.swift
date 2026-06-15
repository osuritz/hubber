import AppKit
import Combine
import Foundation
import Security

struct GitHubDeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresAt: Date
    let interval: Int

    var isExpired: Bool {
        Date() >= expiresAt
    }
}

struct GitHubStoredToken: Codable, Equatable, Sendable {
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

struct GitHubAuthenticatedUser: Decodable, Equatable, Sendable {
    let login: String
}

enum GitHubAuthError: LocalizedError, Equatable, Sendable {
    case invalidResponse
    case authorizationExpired
    case authorizationDenied
    case deviceFlowDisabled
    case badCredentials
    case missingRefreshToken
    case keychain(OSStatus)
    case github(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        case .authorizationExpired:
            return "The GitHub sign-in code expired. Start sign-in again."
        case .authorizationDenied:
            return "GitHub sign-in was cancelled."
        case .deviceFlowDisabled:
            return "Device Flow is not enabled for this GitHub App."
        case .badCredentials:
            return "GitHub rejected the saved credentials. Please sign in again."
        case .missingRefreshToken:
            return "The saved token cannot be refreshed. Please sign in again."
        case .keychain(let status):
            return "Keychain returned status \(status)."
        case .github(let message):
            return message
        }
    }
}

final class GitHubTokenStore: Sendable {
    private let service = "com.osuritz.hubber.github-auth"
    private let account = "github-app-user-token"

    func load() throws -> GitHubStoredToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw GitHubAuthError.keychain(status)
        }
        guard let data = item as? Data else {
            throw GitHubAuthError.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubStoredToken.self, from: data)
    }

    func save(_ token: GitHubStoredToken) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(token)
        var query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        guard status == errSecItemNotFound else {
            throw GitHubAuthError.keychain(status)
        }

        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GitHubAuthError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubAuthError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

final class GitHubAuthService: Sendable {
    private let clientID: String
    private let session: URLSession

    init(clientID: String = GitHubAppConfig.clientID, session: URLSession = .shared) {
        self.clientID = clientID
        self.session = session
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        let response: DeviceCodeResponse = try await postForm(
            url: URL(string: "https://github.com/login/device/code")!,
            parameters: ["client_id": clientID]
        )

        guard let verificationURI = URL(string: response.verificationURI) else {
            throw GitHubAuthError.invalidResponse
        }

        return GitHubDeviceAuthorization(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURI: verificationURI,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            interval: response.interval
        )
    }

    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> GitHubStoredToken {
        var interval = max(deviceAuthorization.interval, 1)

        while !Task.isCancelled && !deviceAuthorization.isExpired {
            try await Task.sleep(for: .seconds(interval))

            let response: TokenResponse = try await postForm(
                url: URL(string: "https://github.com/login/oauth/access_token")!,
                parameters: [
                    "client_id": clientID,
                    "device_code": deviceAuthorization.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
                ]
            )

            if let token = response.storedToken() {
                return token
            }

            switch response.error {
            case "authorization_pending":
                continue
            case "slow_down":
                interval = response.interval ?? interval + 5
            case "expired_token", "token_expired":
                throw GitHubAuthError.authorizationExpired
            case "access_denied":
                throw GitHubAuthError.authorizationDenied
            case "device_flow_disabled":
                throw GitHubAuthError.deviceFlowDisabled
            case .some(let error):
                throw GitHubAuthError.github(response.errorDescription ?? error)
            case nil:
                throw GitHubAuthError.invalidResponse
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }
        throw GitHubAuthError.authorizationExpired
    }

    func refresh(_ token: GitHubStoredToken) async throws -> GitHubStoredToken {
        guard let refreshToken = token.refreshToken, token.canRefresh else {
            throw GitHubAuthError.missingRefreshToken
        }

        let response: TokenResponse = try await postForm(
            url: URL(string: "https://github.com/login/oauth/access_token")!,
            parameters: [
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken
            ]
        )

        if var refreshed = response.storedToken() {
            refreshed.login = token.login
            return refreshed
        }

        if response.error == "bad_refresh_token" {
            throw GitHubAuthError.missingRefreshToken
        }
        let fallback = "GitHub could not refresh the token."
        throw GitHubAuthError.github(response.errorDescription ?? response.error ?? fallback)
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> GitHubAuthenticatedUser {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAuthError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw GitHubAuthError.badCredentials
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubAuthError.github("GitHub returned HTTP \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(GitHubAuthenticatedUser.self, from: data)
    }

    private func postForm<T: Decodable>(url: URL, parameters: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.formURLEncoded().data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw GitHubAuthError.github("GitHub returned HTTP \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

@MainActor
final class HubberStore: ObservableObject {
    @Published private(set) var authState: HubberAuthState = .restoring

    let data = MockGitHubData.sample

    private let authService: GitHubAuthService
    private let tokenStore: GitHubTokenStore
    private var authTask: Task<Void, Never>?

    init(
        authService: GitHubAuthService = GitHubAuthService(),
        tokenStore: GitHubTokenStore = GitHubTokenStore()
    ) {
        self.authService = authService
        self.tokenStore = tokenStore
        restoreSession()
    }

    var usernameDisplay: String {
        switch authState {
        case .signedIn(let login):
            return "· @\(login)"
        case .waitingForUser:
            return "· signing in"
        case .restoring:
            return "· loading"
        case .signedOut:
            return "· not signed in"
        case .error:
            return "· auth error"
        }
    }

    func restoreSession() {
        authTask?.cancel()
        authTask = Task {
            var cachedLogin: String?

            do {
                guard var token = try await loadStoredToken() else {
                    authState = .signedOut
                    return
                }

                cachedLogin = token.login
                if let login = cachedLogin {
                    authState = .signedIn(login: login)
                } else {
                    authState = .restoring
                }

                if !token.hasFreshAccessToken {
                    token = try await authService.refresh(token)
                }

                let user: GitHubAuthenticatedUser
                do {
                    user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
                } catch GitHubAuthError.badCredentials where token.canRefresh {
                    token = try await authService.refresh(token)
                    user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
                }

                token.login = user.login
                try await saveStoredToken(token)
                authState = .signedIn(login: user.login)
            } catch GitHubAuthError.badCredentials, GitHubAuthError.missingRefreshToken {
                try? await deleteStoredToken()
                authState = .signedOut
            } catch {
                if let cachedLogin {
                    authState = .signedIn(login: cachedLogin)
                } else {
                    authState = .error(error.localizedDescription)
                }
            }
        }
    }

    func startSignIn() {
        authTask?.cancel()
        authTask = Task {
            do {
                authState = .restoring
                let deviceAuthorization = try await authService.startDeviceFlow()
                authState = .waitingForUser(deviceAuthorization)
                NSWorkspace.shared.open(deviceAuthorization.verificationURI)

                var token = try await authService.pollForToken(deviceAuthorization: deviceAuthorization)
                let user = try await authService.fetchAuthenticatedUser(accessToken: token.accessToken)
                token.login = user.login
                try await saveStoredToken(token)
                authState = .signedIn(login: user.login)
            } catch is CancellationError {
                authState = .signedOut
            } catch {
                authState = .error(error.localizedDescription)
            }
        }
    }

    func cancelSignIn() {
        authTask?.cancel()
        authTask = nil
        authState = .signedOut
    }

    func signOut() {
        authTask?.cancel()
        authTask = Task {
            do {
                try await deleteStoredToken()
                authState = .signedOut
            } catch {
                authState = .error(error.localizedDescription)
            }
        }
    }

    func openDeviceVerificationPage() {
        if case .waitingForUser(let authorization) = authState {
            NSWorkspace.shared.open(authorization.verificationURI)
        }
    }

    func copyDeviceCode() {
        if case .waitingForUser(let authorization) = authState {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(authorization.userCode, forType: .string)
        }
    }

    private func loadStoredToken() async throws -> GitHubStoredToken? {
        let tokenStore = tokenStore
        return try await Task.detached(priority: .utility) {
            try tokenStore.load()
        }.value
    }

    private func saveStoredToken(_ token: GitHubStoredToken) async throws {
        let tokenStore = tokenStore
        try await Task.detached(priority: .utility) {
            try tokenStore.save(token)
        }.value
    }

    private func deleteStoredToken() async throws {
        let tokenStore = tokenStore
        try await Task.detached(priority: .utility) {
            try tokenStore.delete()
        }.value
    }
}

enum HubberAuthState: Equatable, Sendable {
    case restoring
    case signedOut
    case waitingForUser(GitHubDeviceAuthorization)
    case signedIn(login: String)
    case error(String)
}

private struct DeviceCodeResponse: Decodable, Sendable {
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

private struct TokenResponse: Decodable, Sendable {
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

private extension Dictionary where Key == String, Value == String {
    func formURLEncoded() -> String {
        map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .sorted()
        .joined(separator: "&")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}

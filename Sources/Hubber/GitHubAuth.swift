import Foundation

// MARK: - GitHub device-flow authentication

//
// Device flow is a GitHub OAuth feature. `GitHubDeviceFlowServicing` refines the neutral
// `CodeHostAuthServicing` (Core/CodeHostModels.swift); `GitHubAuthService` is the real impl.
// Token storage lives in Core/TokenStore.swift.

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

protocol GitHubDeviceFlowServicing: CodeHostAuthServicing {
    func startDeviceFlow() async throws -> GitHubDeviceAuthorization
    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> StoredToken
}

typealias GitHubAuthServicing = GitHubDeviceFlowServicing

final class GitHubAuthService: GitHubAuthServicing, Sendable {
    private let clientID: String
    private let session: URLSession
    private let endpoints: GitHubEndpoints

    init(
        clientID: String = GitHubAppConfig.clientID,
        baseURL: URL = GitHubEndpoints.dotComWebBaseURL,
        session: URLSession = .shared
    ) {
        self.clientID = clientID
        endpoints = GitHubEndpoints(webBaseURL: baseURL)
        self.session = session
    }

    func startDeviceFlow() async throws -> GitHubDeviceAuthorization {
        let response: DeviceCodeResponse = try await postForm(
            url: endpoints.deviceCode,
            parameters: ["client_id": clientID]
        )

        guard let verificationURI = URL(string: response.verificationURI) else {
            throw CodeHostAuthError.invalidResponse
        }

        return GitHubDeviceAuthorization(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            verificationURI: verificationURI,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            interval: response.interval
        )
    }

    func pollForToken(deviceAuthorization: GitHubDeviceAuthorization) async throws -> StoredToken {
        var interval = max(deviceAuthorization.interval, 1)

        while !Task.isCancelled, !deviceAuthorization.isExpired {
            try await Task.sleep(for: .seconds(interval))

            let response: TokenResponse = try await postForm(
                url: endpoints.accessToken,
                parameters: [
                    "client_id": clientID,
                    "device_code": deviceAuthorization.deviceCode,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
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
                throw CodeHostAuthError.authorizationExpired
            case "access_denied":
                throw CodeHostAuthError.authorizationDenied
            case "device_flow_disabled":
                throw CodeHostAuthError.deviceFlowDisabled
            case let .some(error):
                throw CodeHostAuthError.providerMessage(response.errorDescription ?? error)
            case nil:
                throw CodeHostAuthError.invalidResponse
            }
        }

        if Task.isCancelled {
            throw CancellationError()
        }
        throw CodeHostAuthError.authorizationExpired
    }

    func refresh(_ token: StoredToken) async throws -> StoredToken {
        guard let refreshToken = token.refreshToken, token.canRefresh else {
            throw CodeHostAuthError.missingRefreshToken
        }

        let response: TokenResponse = try await postForm(
            url: endpoints.accessToken,
            parameters: [
                "client_id": clientID,
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ]
        )

        if var refreshed = response.storedToken() {
            refreshed.login = token.login
            return refreshed
        }

        if response.error == "bad_refresh_token" {
            throw CodeHostAuthError.missingRefreshToken
        }
        let fallback = "GitHub could not refresh the token."
        throw CodeHostAuthError.providerMessage(response.errorDescription ?? response.error ?? fallback)
    }

    func fetchAuthenticatedUser(accessToken: String) async throws -> AuthenticatedUser {
        var request = URLRequest(url: endpoints.authenticatedUser)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodeHostAuthError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw CodeHostAuthError.badCredentials
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodeHostAuthError.providerMessage("GitHub returned HTTP \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(AuthenticatedUser.self, from: data)
    }

    private func postForm<T: Decodable>(url: URL, parameters: [String: String]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.formURLEncoded().data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodeHostAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodeHostAuthError.providerMessage("GitHub returned HTTP \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

import Foundation
import XCTest
@testable import Hubber

final class GitHubAuthServiceRoutingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testStartDeviceFlowRoutesToGHESLoginHost() async throws {
        MockURLProtocol.handler = { request in
            try (Self.ok(for: request), Self.deviceCodeResponse)
        }
        let service = try GitHubAuthService(
            clientID: "client-123",
            baseURL: XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await service.startDeviceFlow()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.enterprise.acme.com/login/device/code")
    }

    func testFetchAuthenticatedUserRoutesToGHESRestV3() async throws {
        MockURLProtocol.handler = { request in
            try (Self.ok(for: request), Self.userResponse)
        }
        let service = try GitHubAuthService(
            clientID: "client-123",
            baseURL: XCTUnwrap(URL(string: "https://github.enterprise.acme.com")),
            session: makeSession()
        )

        _ = try await service.fetchAuthenticatedUser(accessToken: "ghes-secret")

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.enterprise.acme.com/api/v3/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghes-secret")
    }

    func testDefaultsPreserveDotComEndpoints() async throws {
        MockURLProtocol.handler = { request in
            try (Self.ok(for: request), Self.deviceCodeResponse)
        }
        let service = GitHubAuthService(clientID: "client-123", session: makeSession())

        _ = try await service.startDeviceFlow()

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://github.com/login/device/code")
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func ok(for request: URLRequest) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    private static let deviceCodeResponse = Data("""
    {
      "device_code": "dc-1",
      "user_code": "WDJB-MJHT",
      "verification_uri": "https://github.enterprise.acme.com/login/device",
      "expires_in": 900,
      "interval": 5
    }
    """.utf8)

    private static let userResponse = Data("""
    { "login": "enterprise-user", "name": "Enterprise User", "avatar_url": "https://example.com/a.png" }
    """.utf8)
}

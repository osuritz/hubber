import Foundation
import XCTest
@testable import Hubber

final class GitLabAuthServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testFetchAuthenticatedUserMapsCurrentUser() async throws {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            ))
            let body = Data("""
            { "data": { "currentUser": { "username": "osuritz", "name": "Olivier", "avatarUrl": "https://x/a.png" } } }
            """.utf8)
            return (response, body)
        }
        let service = try GitLabAuthService(
            baseURL: XCTUnwrap(URL(string: "https://gitlab.com")),
            session: makeSession()
        )

        let user = try await service.fetchAuthenticatedUser(accessToken: "glpat-x")

        XCTAssertEqual(user.login, "osuritz")
        XCTAssertEqual(user.name, "Olivier")
        XCTAssertEqual(MockURLProtocol.lastRequest?.url?.absoluteString, "https://gitlab.com/api/graphql")
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer glpat-x")
    }

    func testFetchAuthenticatedUserThrowsBadCredentialsOn401() async {
        MockURLProtocol.handler = { request in
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            ))
            return (response, Data())
        }
        let service = GitLabAuthService(session: makeSession())
        do {
            _ = try await service.fetchAuthenticatedUser(accessToken: "bad")
            XCTFail("expected badCredentials")
        } catch GitHubAuthError.badCredentials {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testDeviceFlowAndRefreshAreUnsupported() async {
        let service = GitLabAuthService(session: makeSession())
        do { _ = try await service.startDeviceFlow()
            XCTFail("expected unsupported device flow")
        } catch { /* expected */ }
        let token = GitHubStoredToken(
            accessToken: "x",
            accessTokenExpiresAt: nil,
            refreshToken: nil,
            refreshTokenExpiresAt: nil,
            tokenType: "bearer",
            login: "osuritz"
        )
        do { _ = try await service.refresh(token)
            XCTFail("expected missing refresh token")
        } catch GitHubAuthError.missingRefreshToken {
            // expected
        } catch { XCTFail("wrong error: \(error)") }
    }
}

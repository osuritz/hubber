import Foundation
import XCTest
@testable import Hubber

final class GitHubProviderDraftTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testFetchDraftPullRequestsMapsDraftNodes() async throws {
        let service = GitHubProvider(session: makeSession())
        MockURLProtocol.handler = { request in
            MockURLProtocol.lastRequest = request
            let response = try Self.response(for: request)
            return (response, Self.draftPullRequestsResponse)
        }

        let drafts = try await service.fetchDraftPullRequests(accessToken: "test-token", limit: 10)

        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(drafts.count, 2)
        XCTAssertEqual(drafts.map(\.number), [86, 135])
        XCTAssertEqual(drafts[0].repo, "osuritz/rehearsal")
        XCTAssertEqual(drafts[0].title, "Draft one")
        XCTAssertEqual(drafts[0].url?.absoluteString, "https://github.com/osuritz/rehearsal/pull/86")
        XCTAssertEqual(drafts[0].commits, 3)
        XCTAssertEqual(drafts[0].ci, .noChecks)
        XCTAssertEqual(drafts[0].ciDetail, "No checks")
        let updatedAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-01T07:03:33Z"))
        XCTAssertEqual(drafts[0].updatedAt, updatedAt)
    }

    func testFetchDraftPullRequestsSurfacesGraphQLError() async throws {
        let service = GitHubProvider(session: makeSession())
        MockURLProtocol.handler = { request in
            let response = try Self.response(for: request)
            return (response, Self.graphQLErrorResponse)
        }

        do {
            _ = try await service.fetchDraftPullRequests(accessToken: "test-token")
            XCTFail("Expected CodeHostAuthError.providerMessage")
        } catch let CodeHostAuthError.providerMessage(message) {
            XCTAssertEqual(message, "Resource not accessible by integration")
        }
    }

    func testFetchDraftPullRequestsThrowsBadCredentialsForUnauthorizedResponse() async throws {
        let service = GitHubProvider(session: makeSession())
        MockURLProtocol.handler = { request in
            let response = try Self.response(for: request, statusCode: 401)
            return (response, Data())
        }

        do {
            _ = try await service.fetchDraftPullRequests(accessToken: "expired-token")
            XCTFail("Expected CodeHostAuthError.badCredentials")
        } catch CodeHostAuthError.badCredentials {
            // Expected.
        }
    }

    func testFetchDraftPullRequestsSurfacesServerError() async throws {
        let service = GitHubProvider(session: makeSession())
        MockURLProtocol.handler = { request in
            let response = try Self.response(for: request, statusCode: 503)
            return (response, Data())
        }

        do {
            _ = try await service.fetchDraftPullRequests(accessToken: "test-token")
            XCTFail("Expected CodeHostAuthError.providerMessage")
        } catch let CodeHostAuthError.providerMessage(message) {
            XCTAssertEqual(message, "GitHub returned HTTP 503.")
        }
    }

    func testFetchDraftPullRequestsReturnsEmptyArrayForEmptyNodes() async throws {
        let service = GitHubProvider(session: makeSession())
        MockURLProtocol.handler = { request in
            let response = try Self.response(for: request)
            return (response, Self.emptyPullRequestsResponse)
        }

        let drafts = try await service.fetchDraftPullRequests(accessToken: "test-token")

        XCTAssertTrue(drafts.isEmpty)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func response(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )
        else {
            throw URLError(.badServerResponse)
        }
        return response
    }

    private static let draftPullRequestsResponse = Data("""
    {
      "data": {
        "viewer": {
          "pullRequests": {
            "nodes": [
              {
                "id": "PR_kwDOExample86",
                "number": 86,
                "title": "Draft one",
                "isDraft": true,
                "url": "https://github.com/osuritz/rehearsal/pull/86",
                "updatedAt": "2026-06-01T07:03:33Z",
                "repository": { "nameWithOwner": "osuritz/rehearsal" },
                "commits": { "totalCount": 3 }
              },
              {
                "id": "PR_kwDOExample189",
                "number": 189,
                "title": "Ready PR",
                "isDraft": false,
                "url": "https://github.com/osuritz/rehearsal/pull/189",
                "updatedAt": "2026-06-15T03:52:37Z",
                "repository": { "nameWithOwner": "osuritz/rehearsal" },
                "commits": { "totalCount": 4 }
              },
              {
                "id": "PR_kwDOExample135",
                "number": 135,
                "title": "Draft two",
                "isDraft": true,
                "url": "https://github.com/osuritz/rehearsal/pull/135",
                "updatedAt": "2026-05-28T06:02:44Z",
                "repository": { "nameWithOwner": "osuritz/rehearsal" },
                "commits": { "totalCount": 2 }
              }
            ]
          }
        }
      }
    }
    """.utf8)

    private static let graphQLErrorResponse = Data("""
    {
      "data": null,
      "errors": [
        { "message": "Resource not accessible by integration" }
      ]
    }
    """.utf8)

    private static let emptyPullRequestsResponse = Data("""
    {
      "data": {
        "viewer": {
          "pullRequests": {
            "nodes": []
          }
        }
      }
    }
    """.utf8)
}

final class DevelopmentFileTokenStoreTests: XCTestCase {
    func testTokenRoundTripAndDelete() throws {
        let tokenURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("github-auth-dev.json")
        let store = DevelopmentFileTokenStore(tokenURL: tokenURL)
        let token = StoredToken(
            accessToken: "access",
            accessTokenExpiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            refreshToken: "refresh",
            refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            tokenType: "bearer",
            login: "osuritz"
        )

        try store.save(token)

        XCTAssertEqual(try store.load(), token)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tokenURL.path))

        try store.delete()

        XCTAssertNil(try store.load())
    }
}

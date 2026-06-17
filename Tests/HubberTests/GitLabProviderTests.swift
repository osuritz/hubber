import Foundation
import XCTest
@testable import Hubber

final class GitLabProviderTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testConformsToCodeHostProviderAndStubsReturnEmptyArrays() async throws {
        let provider: any CodeHostProvider = GitLabProvider()

        let incoming = try await provider.fetchIncomingReviews(
            accessToken: "tok",
            viewerLogin: "osuritz",
            mode: .explicit
        )
        let outgoing = try await provider.fetchOutgoingPullRequests(
            accessToken: "tok",
            viewerLogin: "osuritz",
            unresolvedMode: .allOpen
        )
        let drafts = try await provider.fetchDraftPullRequests(accessToken: "tok", limit: 100)

        XCTAssertTrue(incoming.isEmpty)
        XCTAssertTrue(outgoing.isEmpty)
        XCTAssertTrue(drafts.isEmpty)
    }

    func testGraphQLPostsToGitLabEndpointWithBearerTokenAndReturnsData() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.dataResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        let data = try await provider.graphQL(
            query: "query Test { currentUser { username } }",
            variables: ["first": 1],
            accessToken: "glpat-token"
        )

        XCTAssertEqual(
            MockURLProtocol.lastRequest?.url?.absoluteString,
            "https://gitlab.com/api/graphql"
        )
        XCTAssertEqual(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer glpat-token")
        XCTAssertEqual(data["ok"] as? Bool, true)
    }

    func testGraphQL401ThrowsBadCredentials() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request, statusCode: 401), Data())
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        do {
            _ = try await provider.graphQL(
                query: "query Test { currentUser { username } }",
                variables: [:],
                accessToken: "bad"
            )
            XCTFail("Expected badCredentials")
        } catch GitHubAuthError.badCredentials {
            // expected
        }
    }

    func testGraphQL200WithErrorsAndNoDataThrowsGitHubMessage() async throws {
        MockURLProtocol.handler = { request in
            try (Self.response(for: request), Self.errorsResponse)
        }
        let provider = try GitLabProvider(baseURL: XCTUnwrap(URL(string: "https://gitlab.com")), session: makeSession())

        do {
            _ = try await provider.graphQL(
                query: "query Test { currentUser { username } }",
                variables: [:],
                accessToken: "tok"
            )
            XCTFail("Expected github error")
        } catch let GitHubAuthError.github(message) {
            XCTAssertEqual(message, "x")
        }
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private static func response(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
        guard let url = request.url else { throw URLError(.badURL) }
        guard
            let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)
        else { throw URLError(.badServerResponse) }
        return response
    }

    private static let dataResponse = Data("""
    { "data": { "ok": true } }
    """.utf8)

    private static let errorsResponse = Data("""
    { "errors": [{ "message": "x" }] }
    """.utf8)
}

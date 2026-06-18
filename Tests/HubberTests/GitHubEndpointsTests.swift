import Foundation
import XCTest
@testable import Hubber

final class GitHubEndpointsTests: XCTestCase {
    func testDotComDefaultRoutesAPIToApiGitHubCom() {
        let endpoints = GitHubEndpoints()
        XCTAssertTrue(endpoints.isDotCom)
        XCTAssertEqual(endpoints.graphQL.absoluteString, "https://api.github.com/graphql")
        XCTAssertEqual(endpoints.restBase.absoluteString, "https://api.github.com")
        XCTAssertEqual(endpoints.authenticatedUser.absoluteString, "https://api.github.com/user")
        XCTAssertEqual(endpoints.deviceCode.absoluteString, "https://github.com/login/device/code")
        XCTAssertEqual(endpoints.accessToken.absoluteString, "https://github.com/login/oauth/access_token")
    }

    func testGHESKeepsEverythingUnderOneHost() throws {
        let base = try XCTUnwrap(URL(string: "https://github.enterprise.acme.com"))
        let endpoints = GitHubEndpoints(webBaseURL: base)
        XCTAssertFalse(endpoints.isDotCom)
        XCTAssertEqual(endpoints.graphQL.absoluteString, "https://github.enterprise.acme.com/api/graphql")
        XCTAssertEqual(endpoints.restBase.absoluteString, "https://github.enterprise.acme.com/api/v3")
        XCTAssertEqual(endpoints.authenticatedUser.absoluteString, "https://github.enterprise.acme.com/api/v3/user")
        XCTAssertEqual(endpoints.deviceCode.absoluteString, "https://github.enterprise.acme.com/login/device/code")
        XCTAssertEqual(
            endpoints.accessToken.absoluteString,
            "https://github.enterprise.acme.com/login/oauth/access_token"
        )
    }
}

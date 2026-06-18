import Foundation
import XCTest
@testable import Hubber

final class ConnectionFactoryTests: XCTestCase {
    func testGitHubDotComRoutesToGitHubProviderAndAuth() {
        let id = ConnectionID.gitHubDotCom(login: "osuritz")
        let built = ConnectionFactory.providerAndAuth(for: id)
        XCTAssertTrue(built.provider is GitHubProvider || built.provider is CachingCodeHostProvider)
        XCTAssertTrue(built.authService is GitHubAuthService)
    }

    func testGHESRoutesToGitHubProviderAtHost() {
        let id = ConnectionID(provider: "github", host: "github.enterprise.acme.com", login: "osuritz")
        let built = ConnectionFactory.providerAndAuth(for: id)
        XCTAssertTrue(built.authService is GitHubAuthService)
        // Routing to the host is covered by ProviderHostRoutingTests; here we assert the type mapping.
    }

    func testGitLabRoutesToGitLabProviderAndAuth() {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")
        let built = ConnectionFactory.providerAndAuth(for: id)
        XCTAssertTrue(built.provider is GitLabProvider || built.provider is CachingCodeHostProvider)
        XCTAssertTrue(built.authService is GitLabAuthService)
    }

    func testBaseURLDerivedFromHost() {
        let id = ConnectionID(provider: "gitlab", host: "gitlab.intra.acme.com", login: "x")
        XCTAssertEqual(ConnectionFactory.baseURL(for: id).absoluteString, "https://gitlab.intra.acme.com")
    }
}

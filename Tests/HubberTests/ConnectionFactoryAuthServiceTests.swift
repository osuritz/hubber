import Foundation
import XCTest
@testable import Hubber

final class ConnectionFactoryAuthServiceTests: XCTestCase {
    func testGitHubHostBuildsGitHubAuthService() {
        let svc = ConnectionFactory.authService(provider: "github", host: "github.com")
        XCTAssertTrue(svc is GitHubAuthService)
    }

    func testGitLabHostBuildsGitLabAuthService() {
        let svc = ConnectionFactory.authService(provider: "gitlab", host: "gitlab.com")
        XCTAssertTrue(svc is GitLabAuthService)
    }

    func testProviderDisplayName() {
        XCTAssertEqual(ConnectionID.gitHubDotCom(login: "o").providerDisplayName, "GitHub")
        XCTAssertEqual(
            ConnectionID(provider: "github", host: "ghe.acme.com", login: "o").providerDisplayName,
            "GitHub Enterprise"
        )
        XCTAssertEqual(ConnectionID(provider: "gitlab", host: "gitlab.com", login: "o").providerDisplayName, "GitLab")
    }
}

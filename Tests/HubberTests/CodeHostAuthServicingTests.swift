import XCTest
@testable import Hubber

final class CodeHostAuthServicingTests: XCTestCase {
    func testGitHubAuthServiceConformsToBothSeams() {
        let service: any GitHubDeviceFlowServicing = GitHubAuthService()
        let generic: any CodeHostAuthServicing = service

        XCTAssertNotNil(generic)
    }
}

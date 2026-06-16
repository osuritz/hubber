import Foundation
import XCTest
@testable import Hubber

@MainActor
final class HubberAuthStateTests: XCTestCase {

    // MARK: - authState(afterRefreshError:signedInLogin:)

    func testBadCredentialsWithLoginReturnsSessionExpired() {
        let result = HubberStore.authState(
            afterRefreshError: GitHubAuthError.badCredentials,
            signedInLogin: "osuritz"
        )
        XCTAssertEqual(result, .sessionExpired(login: "osuritz"))
    }

    func testMissingRefreshTokenWithLoginReturnsSessionExpired() {
        let result = HubberStore.authState(
            afterRefreshError: GitHubAuthError.missingRefreshToken,
            signedInLogin: "osuritz"
        )
        XCTAssertEqual(result, .sessionExpired(login: "osuritz"))
    }

    func testBadCredentialsWithNilLoginReturnsSignedOut() {
        let result = HubberStore.authState(
            afterRefreshError: GitHubAuthError.badCredentials,
            signedInLogin: nil
        )
        XCTAssertEqual(result, .signedOut)
    }

    func testCancellationErrorReturnsNil() {
        let result = HubberStore.authState(
            afterRefreshError: CancellationError(),
            signedInLogin: "osuritz"
        )
        XCTAssertNil(result)
    }

    func testGenericGitHubErrorReturnsNil() {
        let result = HubberStore.authState(
            afterRefreshError: GitHubAuthError.github("x"),
            signedInLogin: "osuritz"
        )
        XCTAssertNil(result)
    }
}

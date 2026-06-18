import XCTest
@testable import Hubber

final class AccountHeaderLabelTests: XCTestCase {
    private let gh = ConnectionID.gitHubDotCom(login: "osuritz")
    private let gl = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "osuritz")

    func testAllVisible() {
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh, gl], hidden: []), "All accounts")
    }

    func testExactlyOneVisible() {
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh, gl], hidden: [gl]), "GitHub · @osuritz")
    }

    func testPartialSubset() {
        let gl2 = ConnectionID(provider: "gitlab", host: "gitlab.com", login: "other")
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh, gl, gl2], hidden: [gl2]), "2 of 3 accounts")
    }

    func testSingleAccountShowsItsLabel() {
        XCTAssertEqual(AccountHeaderLabel.text(ids: [gh], hidden: []), "GitHub · @osuritz")
    }
}

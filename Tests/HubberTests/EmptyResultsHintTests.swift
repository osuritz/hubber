import XCTest
@testable import Hubber

final class EmptyResultsHintTests: XCTestCase {
    private let empty = HubberData(incoming: [], outgoing: [], drafts: [])

    private func show(
        signedIn: Bool = true,
        lastRefresh: Date? = Date(timeIntervalSinceReferenceDate: 800_000_000),
        error: Bool = false,
        refreshing: Bool = false,
        data: HubberData? = nil
    ) -> Bool {
        EmptyResultsHint.shouldShow(
            hasSignedInConnection: signedIn,
            lastRefresh: lastRefresh,
            hasRefreshError: error,
            isRefreshing: refreshing,
            data: data ?? empty
        )
    }

    func testShowsWhenAllConditionsHold() {
        XCTAssertTrue(show())
    }

    func testHiddenWhenNotSignedIn() {
        XCTAssertFalse(show(signedIn: false))
    }

    func testHiddenBeforeFirstRefresh() {
        XCTAssertFalse(show(lastRefresh: nil))
    }

    func testHiddenOnRefreshError() {
        XCTAssertFalse(show(error: true))
    }

    func testHiddenWhileRefreshing() {
        XCTAssertFalse(show(refreshing: true))
    }

    func testHiddenWhenAnyListHasItems() {
        let sample = HubberData.sample
        XCTAssertFalse(sample.drafts.isEmpty)
        XCTAssertFalse(show(data: sample))
    }

    func testHelpURLTargetsDocsAnchor() {
        XCTAssertEqual(
            EmptyResultsHint.helpURL?.absoluteString,
            "https://github.com/osuritz/hubber/blob/main/docs/token-permissions.md"
                + "#not-seeing-your-organizations-pull-requests"
        )
    }
}

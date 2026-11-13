import XCTest
@testable import Hubber

final class GraphQLDiagnosticsTests: XCTestCase {
    func testTypeAndMessage() {
        let json: [String: Any] = ["errors": [["type": "FORBIDDEN", "message": "SAML enforcement"]]]
        XCTAssertEqual(GraphQLDiagnostics.errorNotes(from: json), ["FORBIDDEN: SAML enforcement"])
    }

    func testMessageOnly() {
        let json: [String: Any] = ["errors": [["message": "boom"]]]
        XCTAssertEqual(GraphQLDiagnostics.errorNotes(from: json), ["boom"])
    }

    func testCapsAtFiveNotes() {
        let errors = (0..<8).map { ["message": "e\($0)"] }
        let notes = GraphQLDiagnostics.errorNotes(from: ["errors": errors])
        XCTAssertEqual(notes, ["e0", "e1", "e2", "e3", "e4"])
    }

    func testTruncatesLongMessage() {
        let json: [String: Any] = ["errors": [["message": String(repeating: "x", count: 500)]]]
        XCTAssertEqual(GraphQLDiagnostics.errorNotes(from: json), [String(repeating: "x", count: 200)])
    }

    func testMissingOrEmptyErrors() {
        XCTAssertEqual(GraphQLDiagnostics.errorNotes(from: [:]), [])
        XCTAssertEqual(GraphQLDiagnostics.errorNotes(from: ["errors": [Any]()]), [])
        XCTAssertEqual(GraphQLDiagnostics.errorNotes(from: ["errors": "nope"]), [])
    }

    func testMalformedEntriesSkipped() {
        let errors: [Any] = ["str", 3, ["type": "X"], ["message": 5], ["message": "ok"]]
        XCTAssertEqual(GraphQLDiagnostics.errorNotes(from: ["errors": errors]), ["ok"])
    }

    func testSSONote() {
        XCTAssertNil(GraphQLDiagnostics.ssoNote(header: nil))
        XCTAssertNil(GraphQLDiagnostics.ssoNote(header: ""))
        XCTAssertEqual(
            GraphQLDiagnostics.ssoNote(header: "required; url=https://github.com/orgs/x/sso?authorization_request=1"),
            "X-GitHub-SSO: required"
        )
        XCTAssertEqual(
            GraphQLDiagnostics.ssoNote(header: "partial-results; organizations=1,2"),
            "X-GitHub-SSO: partial-results"
        )
    }
}

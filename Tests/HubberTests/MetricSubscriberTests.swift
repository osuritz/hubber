import XCTest
@testable import Hubber

/// Tests for the pure `DiagnosticFormatter` which maps `DiagnosticSummary` to log strings.
///
/// Real MetricKit payloads are OS-delivered and cannot be constructed in tests; only the
/// pure formatter — which operates on the value-type `DiagnosticSummary` — is unit-tested here.
final class MetricSubscriberTests: XCTestCase {

    // MARK: Crash formatter

    func testCrashLogLineContainsCrashKind() {
        let summary = DiagnosticSummary(kind: .crash, appVersion: "1.0.0", osVersion: "14.0", diagnosticCount: 1)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.contains("crash"), "Log line must identify diagnostic kind 'crash'")
    }

    func testCrashLogLineContainsAppVersion() {
        let summary = DiagnosticSummary(kind: .crash, appVersion: "2.3.4", osVersion: "14.5", diagnosticCount: 1)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.contains("appVersion=2.3.4"), "Log line must contain appVersion field")
    }

    func testCrashLogLineContainsOsVersion() {
        let summary = DiagnosticSummary(kind: .crash, appVersion: "1.0", osVersion: "15.1", diagnosticCount: 1)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.contains("osVersion=15.1"), "Log line must contain osVersion field")
    }

    func testCrashLogLineContainsCount() {
        let summary = DiagnosticSummary(kind: .crash, appVersion: "1.0", osVersion: "14.0", diagnosticCount: 3)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.contains("count=3"), "Log line must contain diagnostic count")
    }

    func testCrashLogLineContainsMetricKitPrefix() {
        let summary = DiagnosticSummary(kind: .crash, appVersion: "1.0", osVersion: "14.0", diagnosticCount: 1)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.hasPrefix("[MetricKit]"), "Log line must begin with '[MetricKit]' prefix")
    }

    // MARK: Hang formatter

    func testHangLogLineContainsHangKind() {
        let summary = DiagnosticSummary(kind: .hang, appVersion: "1.0.0", osVersion: "14.0", diagnosticCount: 1)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.contains("hang"), "Log line must identify diagnostic kind 'hang'")
    }

    func testHangLogLineContainsAppVersion() {
        let summary = DiagnosticSummary(kind: .hang, appVersion: "3.0.1", osVersion: "14.5", diagnosticCount: 2)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.contains("appVersion=3.0.1"), "Log line must contain appVersion field")
    }

    func testHangLogLineContainsCount() {
        let summary = DiagnosticSummary(kind: .hang, appVersion: "1.0", osVersion: "14.0", diagnosticCount: 5)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertTrue(line.contains("count=5"), "Log line must contain diagnostic count")
    }

    // MARK: Privacy — no PII in formatted output

    func testLogLineContainsNoGitHubLogin() {
        // Simulate a summary built from a payload where metaData might include a login.
        // The formatter must only expose version strings and counts — never user identity.
        let summary = DiagnosticSummary(
            kind: .crash,
            appVersion: "1.0",
            osVersion: "14.0",
            diagnosticCount: 1
        )
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertFalse(line.contains("github.com"), "Log line must not contain any GitHub URL")
        XCTAssertFalse(line.contains("@"), "Log line must not contain a user login")
    }

    // MARK: Format smoke test

    func testLogLineMatchesExpectedFormat() {
        let summary = DiagnosticSummary(kind: .crash, appVersion: "1.2.3", osVersion: "14.5", diagnosticCount: 2)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertEqual(
            line,
            "[MetricKit] crash · appVersion=1.2.3 osVersion=14.5 count=2"
        )
    }

    func testHangLogLineMatchesExpectedFormat() {
        let summary = DiagnosticSummary(kind: .hang, appVersion: "2.0.0", osVersion: "15.0", diagnosticCount: 1)
        let line = DiagnosticFormatter.logLine(for: summary)
        XCTAssertEqual(
            line,
            "[MetricKit] hang · appVersion=2.0.0 osVersion=15.0 count=1"
        )
    }
}

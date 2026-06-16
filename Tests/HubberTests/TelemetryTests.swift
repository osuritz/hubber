import XCTest
@testable import Hubber

// MARK: - Spy sink

/// A `TelemetrySink` that records every `send` call for assertion.
/// Thread-safe so tests can be run from any executor.
final class SpyTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(event: String, params: [String: String])] = []

    var calls: [(event: String, params: [String: String])] {
        lock.withLock { _calls }
    }

    func send(_ event: String, _ params: [String: String]) {
        lock.withLock { _calls.append((event: event, params: params)) }
    }
}

// MARK: - PII allow-list

/// Strings that, if they appear as param values, indicate possible PII leakage.
/// The tests below assert none of these ever appear in a telemetry payload.
private let knownPIIValues: Set = [
    "my-org/secret-repo", // repo name
    "Fix the very secret bug", // PR title
    "pr-9999", // PR number
    "secret-user", // GitHub login
    "https://github.com/my-org", // URL
]

// MARK: - Tests

final class TelemetryTests: XCTestCase {

    private var spy: SpyTelemetrySink!
    private var telemetry: Telemetry!

    override func setUp() {
        super.setUp()
        spy = SpyTelemetrySink()
        telemetry = Telemetry(sink: spy)
    }

    // MARK: Event name + param correctness

    func testSessionOpenedSendsCorrectEvent() {
        telemetry.sessionOpened()
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "session.opened")
        XCTAssertEqual(spy.calls[0].params, [:])
    }

    func testTabSwitchedSendsCorrectEvent() {
        telemetry.tabSwitched(to: .incoming)
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "tab.switched")
        XCTAssertEqual(spy.calls[0].params["tab"], "incoming")
    }

    func testTabSwitchedOutgoing() {
        telemetry.tabSwitched(to: .outgoing)
        XCTAssertEqual(spy.calls[0].params["tab"], "outgoing")
    }

    func testTabSwitchedDrafts() {
        telemetry.tabSwitched(to: .drafts)
        XCTAssertEqual(spy.calls[0].params["tab"], "drafts")
    }

    func testItemOpenedSendsCorrectEvent() {
        telemetry.itemOpened(in: .incoming)
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "item.opened")
        XCTAssertEqual(spy.calls[0].params["tab"], "incoming")
    }

    func testManualRefreshSendsCorrectEvent() {
        telemetry.manualRefresh()
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "refresh.manual")
        XCTAssertEqual(spy.calls[0].params, [:])
    }

    func testSessionCountsSendsCorrectEvent() {
        telemetry.sessionCounts(incoming: 3, outgoing: 1, drafts: 5)
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "session.counts")
        XCTAssertEqual(spy.calls[0].params["incoming"], "3")
        XCTAssertEqual(spy.calls[0].params["outgoing"], "1")
        XCTAssertEqual(spy.calls[0].params["drafts"], "5")
    }

    func testSLODistributionSendsCorrectEvent() {
        telemetry.sloDistribution(green: 2, amber: 1, red: 0)
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "slo.distribution")
        XCTAssertEqual(spy.calls[0].params["green"], "2")
        XCTAssertEqual(spy.calls[0].params["amber"], "1")
        XCTAssertEqual(spy.calls[0].params["red"], "0")
    }

    // MARK: Privacy contract — no PII in any emitted param value

    func testNoPIIInTabSwitched() {
        // Tab names are raw values of WorkTab — not user data.
        telemetry.tabSwitched(to: .incoming)
        telemetry.tabSwitched(to: .outgoing)
        telemetry.tabSwitched(to: .drafts)
        assertNoPII(in: spy.calls)
    }

    func testNoPIIInSessionCounts() {
        telemetry.sessionCounts(incoming: 99, outgoing: 0, drafts: 42)
        assertNoPII(in: spy.calls)
    }

    func testNoPIIInSLODistribution() {
        telemetry.sloDistribution(green: 10, amber: 3, red: 1)
        assertNoPII(in: spy.calls)
    }

    // MARK: Param values are counts or enum raw values only

    func testSessionCountsValuesArePureNumbers() {
        telemetry.sessionCounts(incoming: 7, outgoing: 2, drafts: 0)
        for (_, params) in spy.calls {
            for value in params.values {
                XCTAssertNotNil(
                    Int(value),
                    "session.counts param values must be integers, got '\(value)'"
                )
            }
        }
    }

    func testTabSwitchedParamIsWorkTabRawValue() {
        for tab in WorkTab.allCases {
            telemetry.tabSwitched(to: tab)
        }
        let tabValues = spy.calls.compactMap { $0.params["tab"] }
        XCTAssertEqual(tabValues, WorkTab.allCases.map(\.rawValue))
    }

    // MARK: - Helpers

    private func assertNoPII(
        in calls: [(event: String, params: [String: String])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (event, params) in calls {
            for (key, value) in params {
                XCTAssertFalse(
                    knownPIIValues.contains(value),
                    "Possible PII '\(value)' found in event '\(event)' param '\(key)'",
                    file: file,
                    line: line
                )
            }
        }
    }
}

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

// MARK: - Structural allow-list

/// The complete set of values that are ALLOWED in any telemetry param.
/// Every param value must be an integer string (counts), a WorkTab raw value, a CrashReason raw
/// value, or — only for `app.crashed`'s `frame` — a symbol name from Hubber's own binary.
/// Any other string indicates either PII leakage or an unapproved free-form value.
private let allowedTabRawValues: Set<String> = Set(WorkTab.allCases.map(\.rawValue))
private let allowedCrashReasons: Set<String> = Set(CrashReason.allCases.map(\.rawValue))

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

    // MARK: Param values are counts or enum raw values only (structural allow-list)

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

    /// Exercises EVERY Telemetry facade method and asserts that every param value across
    /// ALL recorded sink calls is either an integer string (counts) or a WorkTab raw value.
    ///
    /// This is a structural allow-list: it grows with the API automatically (any new facade
    /// method that accidentally passes a free-form string will fail this test), replacing the
    /// previous deny-list which could only catch known PII strings.
    func testAllFacadeMethodsEmitOnlyAllowedParamValues() {
        // Exercise every Telemetry facade method.
        telemetry.sessionOpened()
        telemetry.tabSwitched(to: .incoming)
        telemetry.tabSwitched(to: .outgoing)
        telemetry.tabSwitched(to: .drafts)
        telemetry.itemOpened(in: .incoming)
        telemetry.itemOpened(in: .outgoing)
        telemetry.itemOpened(in: .drafts)
        telemetry.manualRefresh()
        telemetry.sessionCounts(incoming: 3, outgoing: 1, drafts: 5)
        telemetry.sloDistribution(green: 2, amber: 1, red: 0)
        telemetry.crashDetected(CrashReport(
            appVersion: "0.1.1",
            osVersion: "Version 26.7.1",
            signal: SIGTRAP,
            exceptionName: nil,
            message: "Fatal error: Duplicate values for key: 'octo-reviewer'",
            frames: [],
            topAppSymbol: "$s6Hubber18NotificationDifferO8snapshot4fromAA14ReviewSnapshotVAA0A4DataV_tFZ"
        ))

        XCTAssertGreaterThan(spy.calls.count, 0, "Expected at least one telemetry call")

        assertAllParamValuesAllowed(in: spy.calls)
    }

    // MARK: - Helpers

    /// Asserts that every param value across all calls is on the structural allow-list for
    /// Telemetry params (see `allowedTabRawValues` above).
    private func assertAllParamValuesAllowed(
        in calls: [(event: String, params: [String: String])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (event, params) in calls {
            for (key, value) in params {
                let isIntegerValue = Int(value) != nil
                let isTabRawValue = allowedTabRawValues.contains(value)
                let isCrashReason = allowedCrashReasons.contains(value)
                let isCrashFrameSymbol = event == "app.crashed" && key == "frame" && CrashReport.isSymbolName(value)
                XCTAssertTrue(
                    isIntegerValue || isTabRawValue || isCrashReason || isCrashFrameSymbol,
                    "Param value '\(value)' in event '\(event)' key '\(key)' "
                        + "is not on the telemetry allow-list — "
                        + "possible PII or unapproved free-form string",
                    file: file,
                    line: line
                )
            }
        }
    }
}

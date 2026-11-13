import XCTest
@testable import Hubber

// MARK: - Fixtures

/// A marker as the signal handler writes it: launch header, then `signal NN` + backtrace. The
/// frames mirror the real reviewer-duplicate crash (handler, trampoline, stdlib, app code), with
/// `backtrace_symbols_fd`'s column padding collapsed and the stdlib symbols shortened.
private let signalMarker = """
app-version: 0.1.1
os-version: Version 26.7.1 (Build 25G241)
image: Hubber
signal 05
0 Hubber 0x00000001004b0eb8 $s6Hubber18crashSignalHandleryys5Int32VF + 232
1 libsystem_platform.dylib 0x0000000199538144 _sigtramp + 56
2 libswiftCore.dylib 0x00000001adbf8d4c $ss17_assertionFailure__4file4line5flagsyyF + 216
3 Hubber 0x00000001004b1608 $ss17_NativeDictionaryV5merge20trappingOnDuplicatesyyF + 452
4 Hubber 0x00000001004b1718 $s6Hubber18NotificationDifferO8snapshot4fromAA14ReviewSnapshotVAA0A4DataV_tFZ + 252
5 Hubber 0x00000001004b0c34 main + 484

"""

private let sessionLogWithFatalError = """
2026-11-11T00:35:20Z Refreshing all tabs for @osuritz
2026-11-11T00:35:21Z Fetched 2 incoming, 5 outgoing, 1 drafts
Swift/arm64e-apple-macos.swiftinterface:16201: Fatal error: Duplicate values for key: 'octo-reviewer'

"""

private let appSnapshotSymbol = "$s6Hubber18NotificationDifferO8snapshot4fromAA14ReviewSnapshotVAA0A4DataV_tFZ"

// MARK: - Parsing

final class CrashReportTests: XCTestCase {

    func testHeaderOnlyMarkerMeansThePreviousRunExitedNormally() {
        let marker = "app-version: 0.1.1\nos-version: Version 26.7.1\nimage: Hubber\n"
        XCTAssertNil(CrashReport.parse(marker: marker, sessionLog: sessionLogWithFatalError))
    }

    func testSignalMarkerParsesSignalMessageAndAppFrame() throws {
        let report = try XCTUnwrap(CrashReport.parse(marker: signalMarker, sessionLog: sessionLogWithFatalError))

        XCTAssertEqual(report.appVersion, "0.1.1")
        XCTAssertEqual(report.osVersion, "Version 26.7.1 (Build 25G241)")
        XCTAssertEqual(report.signal, SIGTRAP)
        XCTAssertEqual(report.signalName, "SIGTRAP")
        XCTAssertNil(report.exceptionName)
        XCTAssertEqual(report.reason, .duplicateDictionaryKey)
        XCTAssertEqual(report.message?.hasSuffix("Fatal error: Duplicate values for key: 'octo-reviewer'"), true)
        // Handler + trampoline frames are dropped; the stdlib specialization inside the app image is
        // skipped in favour of the first frame of Hubber's own code.
        XCTAssertEqual(report.frames.count, 4)
        XCTAssertEqual(report.frames.first?.contains("_assertionFailure"), true)
        XCTAssertEqual(report.topAppSymbol, appSnapshotSymbol)
    }

    func testSignalWithoutCapturedMessageIsClassifiedAsOther() throws {
        let report = try XCTUnwrap(CrashReport.parse(marker: signalMarker, sessionLog: ""))
        XCTAssertNil(report.message)
        XCTAssertEqual(report.reason, .other)
        XCTAssertEqual(report.topAppSymbol, appSnapshotSymbol)
    }

    func testExceptionMarkerUsesTheExceptionsOwnCallStack() throws {
        let marker = """
        app-version: 0.1.1
        os-version: Version 26.7.1
        image: Hubber
        exception: NSInvalidArgumentException
        reason: -[NSNull length]: unrecognized selector sent to instance 0x1f2e3d4c
        0 CoreFoundation 0x000000019a0c1e80 __exceptionPreprocess + 176
        1 Hubber 0x0000000100a1b2c4 $s6Hubber11AvatarCacheC5image3forySo7NSImageCSgyYaF + 88
        signal 06
        0 Hubber 0x00000001004b0eb8 $s6Hubber18crashSignalHandleryys5Int32VF + 232
        1 libsystem_platform.dylib 0x0000000199538144 _sigtramp + 56
        2 libsystem_c.dylib 0x0000000199400000 abort + 124

        """
        let report = try XCTUnwrap(CrashReport.parse(marker: marker, sessionLog: ""))

        XCTAssertEqual(report.signal, SIGABRT)
        XCTAssertEqual(report.exceptionName, "NSInvalidArgumentException")
        XCTAssertEqual(report.reason, .objcException)
        XCTAssertEqual(report.message, "-[NSNull length]: unrecognized selector sent to instance 0x1f2e3d4c")
        XCTAssertEqual(report.frames.count, 2)
        XCTAssertEqual(report.topAppSymbol, "$s6Hubber11AvatarCacheC5image3forySo7NSImageCSgyYaF")
    }

    func testTopAppSymbolIsUnknownWhenNoAppFrameOrSymbolIsNotAPlainName() {
        let systemOnly = ["0 libswiftCore.dylib 0x00000001adbf8d4c $ss17_assertionFailure + 216"]
        XCTAssertEqual(CrashReport.topAppSymbol(in: systemOnly, image: "Hubber"), "unknown")

        let objcSelector = ["0 Hubber 0x0000000100a1b2c4 -[Secret token:] + 88"]
        XCTAssertEqual(CrashReport.topAppSymbol(in: objcSelector, image: "Hubber"), "unknown")
    }

    func testFatalMessageTakesTheLastFatalLine() {
        let log = "a.swift:1: Fatal error: first\nnoise\nb.swift:2: Fatal error: second\ntrailing noise\n"
        XCTAssertEqual(CrashReport.fatalMessage(in: log), "b.swift:2: Fatal error: second")
        XCTAssertNil(CrashReport.fatalMessage(in: "nothing fatal here\n"))
    }

    func testReasonClassification() {
        let cases: [(String, CrashReason)] = [
            ("Fatal error: Duplicate values for key: 'x'", .duplicateDictionaryKey),
            ("Fatal error: Index out of range", .indexOutOfRange),
            ("Fatal error: Can't remove last element from an empty collection", .indexOutOfRange),
            ("Fatal error: Unexpectedly found nil while unwrapping an Optional value", .nilUnwrap),
            ("Fatal error: Double value cannot be converted to Int because it is infinite", .numericConversion),
            ("Fatal error: Division by zero", .divisionByZero),
            ("Fatal error: Range requires lowerBound <= upperBound", .invalidRange),
            ("Fatal error: something new", .other),
        ]
        for (message, expected) in cases {
            XCTAssertEqual(CrashReason.classify(message: message, isException: false), expected, message)
        }
        XCTAssertEqual(CrashReason.classify(message: nil, isException: false), .other)
        XCTAssertEqual(CrashReason.classify(message: "Index out of range", isException: true), .objcException)
    }

    func testLogTextCarriesTheFullMessageAndBacktraceForLocalDiagnosis() throws {
        let report = try XCTUnwrap(CrashReport.parse(marker: signalMarker, sessionLog: sessionLogWithFatalError))
        let text = report.logText

        XCTAssertTrue(text.contains("Signal: SIGTRAP"))
        XCTAssertTrue(text.contains("Reason: duplicateDictionaryKey"))
        XCTAssertTrue(text.contains("Duplicate values for key: 'octo-reviewer'"))
        XCTAssertTrue(text.contains("Crashed in: \(appSnapshotSymbol)"))
        XCTAssertTrue(text.contains("_assertionFailure"))
    }
}

// MARK: - Collecting the previous run's report from disk

final class CrashReporterCollectionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrashReporterTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func crashLogs() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("crash-") && $0.hasSuffix(".log") }
            .sorted()
    }

    func testNoMarkerOrCleanMarkerYieldsNoReport() throws {
        XCTAssertNil(CrashReporter.collectPendingReport(in: directory))

        try write("app-version: 0.1.1\nimage: Hubber\n", to: "crash-marker.txt")
        XCTAssertNil(CrashReporter.collectPendingReport(in: directory))
        XCTAssertEqual(try crashLogs(), [])
    }

    func testCrashMarkerBecomesACrashLogAndIsConsumed() throws {
        try write(signalMarker, to: "crash-marker.txt")
        try write(sessionLogWithFatalError, to: "hubber.log")

        let report = try XCTUnwrap(CrashReporter.collectPendingReport(in: directory))
        XCTAssertEqual(report.reason, .duplicateDictionaryKey)

        let logs = try crashLogs()
        XCTAssertEqual(logs.count, 1)
        let text = try String(contentsOf: directory.appendingPathComponent(XCTUnwrap(logs.first)), encoding: .utf8)
        XCTAssertTrue(text.contains("Duplicate values for key: 'octo-reviewer'"))
        XCTAssertTrue(text.contains("Fetched 2 incoming, 5 outgoing, 1 drafts"), "breadcrumbs before the crash")

        // Consumed: the same crash is never reported twice.
        XCTAssertNil(CrashReporter.collectPendingReport(in: directory))
        XCTAssertEqual(try crashLogs().count, 1)
    }

    func testOnlyTheNewestCrashLogsAreKept() throws {
        for index in 0..<(CrashReporter.maxKeptReports + 3) {
            try write("old", to: String(format: "crash-20200101-0000%02d.log", index))
        }
        try write(signalMarker, to: "crash-marker.txt")

        XCTAssertNotNil(CrashReporter.collectPendingReport(in: directory))

        let logs = try crashLogs()
        XCTAssertEqual(logs.count, CrashReporter.maxKeptReports)
        XCTAssertFalse(logs.contains("crash-20200101-000000.log"), "oldest reports are pruned first")
    }
}

// MARK: - Telemetry privacy

final class CrashTelemetryTests: XCTestCase {

    /// The fatal message here contains a login. Nothing derived from it may reach the sink: only
    /// the signal number, the closed-vocabulary reason, and a symbol from Hubber's own binary.
    func testCrashEventNeverCarriesTheFatalMessage() throws {
        let spy = SpyTelemetrySink()
        let report = try XCTUnwrap(CrashReport.parse(marker: signalMarker, sessionLog: sessionLogWithFatalError))

        Telemetry(sink: spy).crashDetected(report)

        XCTAssertEqual(spy.calls.count, 1)
        let call = try XCTUnwrap(spy.calls.first)
        XCTAssertEqual(call.event, "app.crashed")
        XCTAssertEqual(call.params, ["signal": "5", "reason": "duplicateDictionaryKey", "frame": appSnapshotSymbol])
        XCTAssertFalse(call.params.values.contains { $0.contains("octo-reviewer") || $0.contains("Fatal error") })
    }
}

import Darwin
import Foundation
import os

// Swift has no ErrorBoundary: a trap (failed precondition, force unwrap, duplicate dictionary key…)
// cannot be caught or recovered from. What CAN be done is to record why the process died so the
// next launch can report it. This file does that:
//
//   1. stderr is pointed at a session log, because that is where the Swift runtime prints its
//      "Fatal error: …" line — the one piece macOS's own crash report leaves out.
//   2. A signal handler writes the fatal signal + a symbolized backtrace to a marker file, then
//      lets the crash proceed so macOS still produces its normal report.
//   3. On the next launch the marker is turned into `crash-<date>.log` and a `CrashReport`.

// MARK: - Signal-handler state

// Plain globals: the handler may only touch memory that already exists (no allocation, no locks).

/// Open descriptor of the armed crash marker, or -1.
private nonisolated(unsafe) var crashMarkerFD: Int32 = -1
/// Preallocated room for the backtrace.
private nonisolated(unsafe) var crashFrameBuffer: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
/// Preallocated "signal NN\n" line; the handler only patches the two digits.
private nonisolated(unsafe) var crashSignalLine: UnsafeMutablePointer<UInt8>?
/// True once stderr has been redirected to the session log (see `CrashReporter.note`).
private nonisolated(unsafe) var sessionLogActive = false

private func crashSignalHandler(_ sig: Int32) {
    // Restore the default action first. SA_RESETHAND does not apply to SIGTRAP/SIGILL, and without
    // this the faulting instruction would re-run into this handler forever.
    signal(sig, SIG_DFL)
    // If anything below deadlocks (backtrace_symbols_fd takes the loader lock), die anyway.
    alarm(5)

    let fd = crashMarkerFD
    guard fd >= 0, let frames = crashFrameBuffer, let line = crashSignalLine else { return }
    line[7] = 0x30 + UInt8(truncatingIfNeeded: (sig / 10) % 10)
    line[8] = 0x30 + UInt8(truncatingIfNeeded: sig % 10)
    _ = write(fd, line, 10)
    backtrace_symbols_fd(frames, backtrace(frames, 64), fd)
    // Returning re-executes the faulting instruction (or lets abort() re-raise) with the default
    // action, so the process dies with the original signal and macOS writes its crash report.
}

// MARK: - CrashReporter

enum CrashReporter {
    private static let log = Logger(subsystem: "com.hubber.app", category: "Crash")
    private static let fatalSignals = [SIGTRAP, SIGILL, SIGABRT, SIGSEGV, SIGBUS, SIGFPE]
    private static let markerName = "crash-marker.txt"
    private static let sessionLogName = "hubber.log"
    private static let previousSessionLogName = "hubber.previous.log"
    private static let maxSessionLogBytes: off_t = 2 * 1024 * 1024
    static let maxKeptReports = 10

    /// `~/Library/Logs/Hubber` — also browsable in Console.app under "Log Reports".
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Hubber", isDirectory: true)
    }

    /// Collects the report the previous run left behind (if it crashed), then arms capture for
    /// this run. Call once, as early as possible in launch.
    static func start(directory: URL = defaultDirectory) -> CrashReport? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let report = collectPendingReport(in: directory)
        rotateSessionLog(in: directory)
        sessionLogActive = redirectStderrIfDetached(to: directory.appendingPathComponent(sessionLogName))
        arm(marker: directory.appendingPathComponent(markerName))
        return report
    }

    /// Appends a timestamped line to the session log: the breadcrumbs that end up next to a crash.
    /// No-op unless stderr was redirected, so tests and terminal runs stay quiet.
    static func note(_ message: String) {
        guard sessionLogActive else { return }
        if lseek(STDERR_FILENO, 0, SEEK_END) > maxSessionLogBytes {
            ftruncate(STDERR_FILENO, 0)
        }
        FileHandle.standardError.write(Data("\(Date().ISO8601Format()) \(message)\n".utf8))
    }

    /// Deliberately traps the same way the reviewer-duplicate crash did, so the whole pipeline can
    /// be exercised on a release build: `open Hubber.app --env HUBBER_CRASH_SELFTEST=1`.
    static func crashIfSelfTestRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard environment["HUBBER_CRASH_SELFTEST"] != nil else { return }
        let keys = Array(repeating: "crash-self-test", count: 2)
        _ = Dictionary(uniqueKeysWithValues: keys.map { ($0, 0) })
    }

    // MARK: - Previous run

    /// Turns a crash marker left by the previous run into `crash-<date>.log` and returns the parsed
    /// report. Returns nil (and writes nothing) when the previous run exited normally.
    static func collectPendingReport(in directory: URL) -> CrashReport? {
        let markerURL = directory.appendingPathComponent(markerName)
        guard let marker = try? String(contentsOf: markerURL, encoding: .utf8) else { return nil }
        let sessionLog = tail(of: directory.appendingPathComponent(sessionLogName))
        guard let report = CrashReport.parse(marker: marker, sessionLog: sessionLog) else { return nil }

        let crashDate = (try? markerURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let reportURL = directory.appendingPathComponent("crash-\(formatter.string(from: crashDate)).log")
        let recentLog = sessionLog.split(separator: "\n").suffix(40).joined(separator: "\n")
        let text = report.logText + "\nLast log lines before the crash:\n" + recentLog + "\n"
        try? text.write(to: reportURL, atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: markerURL)
        pruneReports(in: directory)

        let (signal, reason, symbol) = (report.signalName, report.reason.rawValue, report.topAppSymbol)
        log.error(
            """
            Previous run crashed: \(signal, privacy: .public) \(reason, privacy: .public) \
            in \(symbol, privacy: .public) — details in \(reportURL.path, privacy: .public)
            """
        )
        return report
    }

    private static func pruneReports(in directory: URL) {
        let reports = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("crash-") && $0.hasSuffix(".log") }
            .sorted()
        for name in reports.dropLast(maxKeptReports) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    /// Last ~64 KB of a file as text ("" if it does not exist).
    private static func tail(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 65536 ? size - 65536 : 0)
        // Lossy on purpose: the 64 KB cut can land mid-character, which must not discard the tail.
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
    }

    // MARK: - This run

    /// Keeps exactly one previous session log, so a stale "Fatal error" line can never be
    /// attributed to a later crash.
    private static func rotateSessionLog(in directory: URL) {
        let current = directory.appendingPathComponent(sessionLogName)
        let previous = directory.appendingPathComponent(previousSessionLogName)
        try? FileManager.default.removeItem(at: previous)
        try? FileManager.default.moveItem(at: current, to: previous)
    }

    /// Points stderr at `url`, but only when it currently goes nowhere (`/dev/null`, which is what
    /// an app launched from Finder / `open` gets). A terminal or an explicit redirect is left alone.
    private static func redirectStderrIfDetached(to url: URL) -> Bool {
        var current = stat()
        var null = stat()
        guard
            fstat(STDERR_FILENO, &current) == 0, stat("/dev/null", &null) == 0,
            current.st_mode & S_IFMT == S_IFCHR, current.st_rdev == null.st_rdev
        else { return false }

        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return dup2(fd, STDERR_FILENO) >= 0
    }

    private static func arm(marker: URL) {
        let fd = open(marker.path, O_WRONLY | O_CREAT | O_TRUNC | O_APPEND, 0o600)
        guard fd >= 0 else { return }

        let info = Bundle.main.infoDictionary
        let header = """
        app-version: \(info?["CFBundleShortVersionString"] as? String ?? "unknown")
        os-version: \(ProcessInfo.processInfo.operatingSystemVersionString)
        image: \(ProcessInfo.processInfo.processName)

        """
        _ = header.withCString { write(fd, $0, strlen($0)) }

        let line = UnsafeMutablePointer<UInt8>.allocate(capacity: 10)
        line.initialize(from: Array("\(CrashReport.signalPrefix)00\n".utf8), count: 10)
        crashSignalLine = line
        crashFrameBuffer = .allocate(capacity: 64)
        crashMarkerFD = fd

        var action = sigaction()
        action.__sigaction_u.__sa_handler = crashSignalHandler
        sigemptyset(&action.sa_mask)
        for fatalSignal in fatalSignals {
            sigaction(fatalSignal, &action, nil)
        }

        // Objective-C exceptions end in abort(); record what they were before the signal handler
        // adds the (less useful) abort backtrace.
        NSSetUncaughtExceptionHandler { exception in
            let text = "\(CrashReport.exceptionPrefix)\(exception.name.rawValue)\n"
                + "\(CrashReport.reasonPrefix)\(exception.reason ?? "")\n"
                + exception.callStackSymbols.joined(separator: "\n") + "\n"
            _ = text.withCString { write(crashMarkerFD, $0, strlen($0)) }
        }
    }
}

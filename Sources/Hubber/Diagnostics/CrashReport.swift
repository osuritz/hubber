import Foundation

// MARK: - Crash reason (closed vocabulary)

/// Why the process died, as a closed vocabulary.
///
/// The raw fatal-error text can carry user data — "Duplicate values for key: '<a GitHub login>'"
/// is a real example — so it stays in the local crash log. This enum is the only form of the
/// reason that is ever sent as telemetry.
enum CrashReason: String, CaseIterable {
    case duplicateDictionaryKey
    case indexOutOfRange
    case nilUnwrap
    case numericConversion
    case arithmeticOverflow
    case divisionByZero
    case invalidRange
    case objcException
    case other

    /// Ordered: the first needle found in the message wins.
    private static let needles: [(needle: String, reason: CrashReason)] = [
        ("Duplicate values for key", .duplicateDictionaryKey),
        ("Duplicate elements of type", .duplicateDictionaryKey),
        ("Duplicate keys of type", .duplicateDictionaryKey),
        ("Unexpectedly found nil", .nilUnwrap),
        ("Division by zero", .divisionByZero),
        ("Division results in an overflow", .divisionByZero),
        ("cannot be converted to", .numericConversion),
        ("Not enough bits to represent", .numericConversion),
        ("Negative value is not representable", .numericConversion),
        ("overflow", .arithmeticOverflow),
        ("Range requires lowerBound", .invalidRange),
        ("Can't form Range", .invalidRange),
        ("out of range", .indexOutOfRange),
        ("out of bounds", .indexOutOfRange),
        ("from an empty collection", .indexOutOfRange),
        ("than it contains", .indexOutOfRange),
    ]

    static func classify(message: String?, isException: Bool) -> CrashReason {
        if isException {
            return .objcException
        }
        guard let message else { return .other }
        return needles.first { message.contains($0.needle) }?.reason ?? .other
    }
}

// MARK: - Crash report

/// What a previous run left behind when it crashed. Built on the NEXT launch from the crash marker
/// (signal + backtrace, written by `CrashReporter`'s signal handler) and the tail of that run's
/// session log (which holds the Swift runtime's "Fatal error: …" line — macOS's own crash report
/// does not include it).
struct CrashReport: Equatable {
    var appVersion: String
    var osVersion: String
    /// The fatal signal, or nil when only an Objective-C exception was recorded.
    var signal: Int32?
    var exceptionName: String?
    /// Full fatal-error / exception text. May contain user data: local log only, never telemetry.
    var message: String?
    /// Backtrace lines of the crashed thread, innermost first, without the signal-handler frames.
    var frames: [String]
    /// The first frame that belongs to Hubber's own code, as a symbol name ("unknown" if none).
    var topAppSymbol: String

    var reason: CrashReason {
        CrashReason.classify(message: message, isException: exceptionName != nil)
    }

    var signalName: String {
        guard let signal else { return "none" }
        return Self.signalNames[signal] ?? "signal \(signal)"
    }

    private static let signalNames: [Int32: String] = [
        SIGILL: "SIGILL", SIGTRAP: "SIGTRAP", SIGABRT: "SIGABRT",
        SIGFPE: "SIGFPE", SIGBUS: "SIGBUS", SIGSEGV: "SIGSEGV",
    ]

    /// Human-readable report for the local crash log.
    var logText: String {
        var lines = [
            "Hubber crash report",
            "App version: \(appVersion)",
            "macOS: \(osVersion)",
            "Signal: \(signalName)",
        ]
        if let exceptionName {
            lines.append("Exception: \(exceptionName)")
        }
        lines.append("Reason: \(reason.rawValue)")
        lines.append("Message: \(message ?? "(none captured)")")
        lines.append("Crashed in: \(topAppSymbol)")
        lines.append("")
        lines.append("Backtrace:")
        lines.append(contentsOf: frames)
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Parsing

extension CrashReport {
    static let signalPrefix = "signal "
    static let exceptionPrefix = "exception: "
    static let reasonPrefix = "reason: "

    /// Parses a crash marker. Returns nil when the marker holds only its header, i.e. the previous
    /// run exited normally.
    ///
    /// Marker layout: `key: value` header lines written at launch, then — only if the run crashed —
    /// an optional `exception:` / `reason:` / call-stack block and/or a `signal NN` line followed by
    /// `backtrace_symbols_fd` output.
    static func parse(marker: String, sessionLog: String) -> CrashReport? {
        let lines = marker.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let crashStart = lines.firstIndex(where: { isSignalLine($0) || $0.hasPrefix(exceptionPrefix) }) else {
            return nil
        }

        var header: [String: String] = [:]
        for line in lines[..<crashStart] {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                header[String(parts[0])] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }

        let body = Array(lines[crashStart...])
        let signalIndex = body.firstIndex(where: isSignalLine)
        let signal = signalIndex.flatMap { Int32(body[$0].dropFirst(signalPrefix.count)) }
        let exceptionName = body.first { $0.hasPrefix(exceptionPrefix) }
            .map { String($0.dropFirst(exceptionPrefix.count)) }
        let exceptionReason = body.first { $0.hasPrefix(reasonPrefix) }
            .map { String($0.dropFirst(reasonPrefix.count)) }

        // An exception's own call stack (recorded before abort() raised the signal) is the
        // interesting one; otherwise use the signal backtrace.
        let frames: [String] = if exceptionName != nil {
            body[..<(signalIndex ?? body.endIndex)].filter(isFrameLine)
        } else {
            framesAfterSignalTrampoline(body[((signalIndex ?? -1) + 1)...].filter(isFrameLine))
        }

        return CrashReport(
            appVersion: header["app-version"] ?? "unknown",
            osVersion: header["os-version"] ?? "unknown",
            signal: signal,
            exceptionName: exceptionName,
            message: exceptionReason ?? fatalMessage(in: sessionLog),
            frames: frames,
            topAppSymbol: topAppSymbol(in: frames, image: header["image"] ?? "Hubber")
        )
    }

    private static func isSignalLine(_ line: String) -> Bool {
        line.hasPrefix(signalPrefix) && Int32(line.dropFirst(signalPrefix.count)) != nil
    }

    /// `backtrace_symbols_fd` / `callStackSymbols` lines start with the frame index.
    private static func isFrameLine(_ line: String) -> Bool {
        line.first?.isNumber == true
    }

    /// Drops the handler's own frames: everything up to and including `_sigtramp`.
    private static func framesAfterSignalTrampoline(_ frames: [String]) -> [String] {
        guard let trampoline = frames.firstIndex(where: { $0.contains("_sigtramp") }) else { return frames }
        return Array(frames[(trampoline + 1)...])
    }

    /// The Swift runtime prints "<file>:<line>: Fatal error: <message>" to stderr just before it
    /// traps; the last such line in the crashed run's session log is the one that killed it.
    static func fatalMessage(in sessionLog: String) -> String? {
        let markers = ["Fatal error", "Precondition failed", "Assertion failed"]
        return sessionLog
            .split(separator: "\n")
            .suffix(200)
            .last { line in markers.contains { line.contains($0) } }
            .map(String.init)
    }

    /// Symbol of the innermost frame in Hubber's own code. Frames in the app image whose symbol is
    /// a standard-library specialization (`$ss…`) are skipped — they say "Dictionary", not where.
    /// The result is restricted to symbol characters so it is safe to send as telemetry.
    static func topAppSymbol(in frames: [String], image: String) -> String {
        for frame in frames {
            let columns = frame.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count >= 4, columns[1] == image else { continue }
            let symbol = String(columns[3])
            if symbol.hasPrefix("$ss") || symbol.hasPrefix("0x") {
                continue
            }
            return isSymbolName(symbol) ? String(symbol.prefix(160)) : "unknown"
        }
        return "unknown"
    }

    /// True for mangled Swift / C symbol names: letters, digits, `_` and `$` only.
    static func isSymbolName(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$")
        }
    }
}

import Foundation
import MetricKit
import os.log

// MARK: - Diagnostic summary (value type — testable without real MX payloads)

/// A lightweight, value-type summary of a MetricKit diagnostic payload.
///
/// This is the only type the formatter touches; it is mappable from real `MXDiagnosticPayload`
/// objects at runtime, but constructable in tests without needing real OS payloads.
struct DiagnosticSummary {
    enum Kind: String {
        case crash
        case hang
    }

    let kind: Kind
    let appVersion: String
    let osVersion: String
    let diagnosticCount: Int
}

// MARK: - Formatter (pure, tested)

/// Pure diagnostic formatter — maps a `DiagnosticSummary` to a human-readable log string.
///
/// The output is intentionally terse and contains no PII: only diagnostic kind, version
/// fields supplied by the OS, and the count of diagnostic reports in the payload.
enum DiagnosticFormatter {
    /// Returns a single-line log string describing a diagnostic summary.
    ///
    /// Example output:
    /// `"[MetricKit] crash · appVersion=1.2.3 osVersion=14.5 count=2"`
    static func logLine(for summary: DiagnosticSummary) -> String {
        "[MetricKit] \(summary.kind.rawValue) · "
            + "appVersion=\(summary.appVersion) "
            + "osVersion=\(summary.osVersion) "
            + "count=\(summary.diagnosticCount)"
    }
}

// MARK: - MetricKit subscriber

/// Subscribes to MetricKit metric and diagnostic payloads.
///
/// Register in `AppDelegate.applicationDidFinishLaunching`:
/// ```swift
/// MXMetricManager.shared.add(metricSubscriber)
/// ```
/// Remove in `applicationWillTerminate`:
/// ```swift
/// MXMetricManager.shared.remove(metricSubscriber)
/// ```
///
/// Real crash/hang diagnostics are delivered by the OS on the next app launch after an event.
/// Only the pure `DiagnosticFormatter` is unit-tested; the subscriber itself is integration-tested
/// via build success and manual verification.
final class MetricSubscriber: NSObject, MXMetricManagerSubscriber {
    private static let log = OSLog(subsystem: "com.hubber.app", category: "MetricKit")

    /// Called with metric payloads (battery, performance, etc.) once per day.
    func didReceive(_ payloads: [MXMetricPayload]) {
        // Log only a controlled, non-PII subset of each metric payload at debug level.
        // Full debugDescription may include device or user-identifiable fields, so it
        // is kept private to the logging subsystem.
        for payload in payloads {
            let appVersion = payload.latestApplicationVersion
            let osVersion = payload.metaData?.osVersion ?? "unknown"
            os_log(
                .debug,
                log: Self.log,
                "MetricKit metric payload received: appVersion=%{public}@ osVersion=%{public}@",
                appVersion,
                osVersion
            )
        }
    }

    /// Called with diagnostic payloads (crashes, hangs) on app launch after an event.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            // Crash diagnostics
            for crash in payload.crashDiagnostics ?? [] {
                let summary = DiagnosticSummary(
                    kind: .crash,
                    appVersion: crash.metaData.applicationBuildVersion,
                    osVersion: crash.metaData.osVersion,
                    diagnosticCount: payload.crashDiagnostics?.count ?? 0
                )
                let line = DiagnosticFormatter.logLine(for: summary)
                os_log(.error, log: Self.log, "%{public}@", line)
            }

            // Hang diagnostics
            for hang in payload.hangDiagnostics ?? [] {
                let summary = DiagnosticSummary(
                    kind: .hang,
                    appVersion: hang.metaData.applicationBuildVersion,
                    osVersion: hang.metaData.osVersion,
                    diagnosticCount: payload.hangDiagnostics?.count ?? 0
                )
                let line = DiagnosticFormatter.logLine(for: summary)
                os_log(.fault, log: Self.log, "%{public}@", line)
            }
        }
    }
}

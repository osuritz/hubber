/// Telemetry sink protocol — any backend that can receive a named event with string parameters.
///
/// Conforming types must be `Sendable` so the facade can be used from any concurrency context.
/// Implementations MUST NOT store user-identifiable data; the `Telemetry` facade enforces this
/// structurally by exposing only typed, privacy-safe event methods.
protocol TelemetrySink: Sendable {
    /// Send a named event with an optional string-keyed parameter dictionary.
    ///
    /// - Parameters:
    ///   - event: Dot-separated event name, e.g. `"session.opened"`.
    ///   - params: Key-value pairs that are ONLY counts or enum raw values — never PII.
    func send(_ event: String, _ params: [String: String])
}

// MARK: - Typed privacy-safe facade

/// A lightweight, typed facade that routes privacy-safe events to a `TelemetrySink`.
///
/// Every method on this type is explicitly designed so that callers **cannot** pass PII:
/// - Session/SLO counts are `Int` — no strings, no labels.
/// - Tab identifiers are `WorkTab.rawValue` (enum raw values, not user data).
///
/// To verify the privacy contract in tests, inject a `SpyTelemetrySink` and assert
/// that none of the recorded param values contain repo names, PR titles, or logins.
struct Telemetry {
    let sink: TelemetrySink

    // MARK: Session lifecycle

    /// Emitted once when the popover opens.
    func sessionOpened() {
        sink.send("session.opened", [:])
    }

    /// Emitted with aggregate item counts when the popover opens.
    func sessionCounts(incoming: Int, outgoing: Int, drafts: Int) {
        sink.send(
            "session.counts",
            ["incoming": "\(incoming)", "outgoing": "\(outgoing)", "drafts": "\(drafts)"]
        )
    }

    // MARK: Tab navigation

    /// Emitted when the user switches to a different tab.
    func tabSwitched(to tab: WorkTab) {
        sink.send("tab.switched", ["tab": tab.rawValue])
    }

    // MARK: Item interaction

    /// Emitted when the user clicks through a row to GitHub.
    func itemOpened(in tab: WorkTab) {
        sink.send("item.opened", ["tab": tab.rawValue])
    }

    // MARK: Refresh

    /// Emitted when the user manually triggers a PR refresh (⌘R or footer button).
    func manualRefresh() {
        sink.send("refresh.manual", [:])
    }

    // MARK: SLO

    /// Emitted with SLO-bucket counts (green/amber/red) for incoming reviews.
    ///
    /// Buckets use the existing SLO ratio logic:
    ///   `ratio = assignedAgoHours / sloHours` → <0.5 green, 0.5–1 amber, ≥1 red.
    func sloDistribution(green: Int, amber: Int, red: Int) {
        sink.send(
            "slo.distribution",
            ["green": "\(green)", "amber": "\(amber)", "red": "\(red)"]
        )
    }
}

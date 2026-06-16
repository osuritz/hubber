import TelemetryDeck

// MARK: - App ID config

/// Telemetry app configuration — alongside `GitHubAppConfig`.
enum TelemetryConfig {
    static let appID = "96FDB900-0C0A-492E-AAC8-E584E6529028"
}

// MARK: - TelemetryDeck sink

/// A `TelemetrySink` backed by the TelemetryDeck Swift SDK.
///
/// - In `#if DEBUG` builds, `testMode` is set to `true` so signals are marked as test
///   signals and will NOT pollute production analytics data.
/// - In release builds, signals are sent normally.
struct TelemetryDeckSink: TelemetrySink {
    /// Initializes the SDK and registers this sink.
    ///
    /// Call once at app launch (e.g. `applicationDidFinishLaunching`).
    ///
    /// **User identity / privacy note:** The TelemetryDeck SDK auto-generates an anonymized,
    /// SHA-256-hashed user identifier derived from a random UUID that is persisted in
    /// UserDefaults on macOS. Hubber never supplies a GitHub login, email address, or any
    /// other PII as the user identifier — the SDK handles identification entirely on its own.
    static func initialize() {
        let config = TelemetryManagerConfiguration(appID: TelemetryConfig.appID)
        #if DEBUG
            config.testMode = true
        #endif
        TelemetryDeck.initialize(config: config)
    }

    func send(_ event: String, _ params: [String: String]) {
        TelemetryDeck.signal(event, parameters: params)
    }
}

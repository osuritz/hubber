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

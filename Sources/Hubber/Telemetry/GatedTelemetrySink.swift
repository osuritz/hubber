import Foundation

/// A `TelemetrySink` that forwards to an underlying sink only while analytics is enabled,
/// consulting the LIVE enabled value before every send so the privacy toggle takes effect
/// immediately (no restart). Lazily initializes the analytics SDK once, just before the first
/// forwarded send. See #103.
final class GatedTelemetrySink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private var initialized = false
    private let underlying: any TelemetrySink
    private let initializeSDK: @Sendable () -> Void

    init(
        enabled: Bool,
        underlying: any TelemetrySink,
        initializeSDK: @escaping @Sendable () -> Void = { TelemetryDeckSink.initialize() }
    ) {
        self.enabled = enabled
        self.underlying = underlying
        self.initializeSDK = initializeSDK
    }

    /// Updates the live enabled value. Safe to call from any thread / executor.
    func setEnabled(_ value: Bool) {
        lock.withLock { enabled = value }
    }

    func send(_ event: String, _ params: [String: String]) {
        let needsInit: Bool = lock.withLock {
            guard enabled else { return false }
            if initialized { return false }
            initialized = true
            return true
        }
        guard lock.withLock({ enabled }) else { return }
        if needsInit { initializeSDK() }
        underlying.send(event, params)
    }
}

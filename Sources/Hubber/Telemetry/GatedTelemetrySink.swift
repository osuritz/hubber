import Foundation

/// A `TelemetrySink` that forwards to an underlying sink only while analytics is enabled,
/// consulting the LIVE enabled value before every send so the privacy toggle takes effect
/// immediately (no restart). Lazily initializes the analytics SDK once, just before the first
/// forwarded send. The enabled-check, the init-once claim, and SDK initialization are all
/// performed under a single lock acquisition so no send can be forwarded to an uninitialized
/// SDK. See #103.
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
        // Decide and (if needed) initialize under a single critical section so the
        // enabled-check, the init-once claim, and the SDK initialization are atomic.
        // initializeSDK() runs under the lock (it is called at most once and must not
        // re-enter this sink); the underlying forward happens OUTSIDE the lock.
        let shouldForward: Bool = lock.withLock {
            guard enabled else { return false }
            if !initialized {
                initialized = true
                initializeSDK()
            }
            return true
        }
        guard shouldForward else { return }
        underlying.send(event, params)
    }
}

import AppKit
import Foundation

@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]
    /// Number of callers currently awaiting each URL's in-flight Task.
    private var waiters: [URL: Int] = [:]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch (or return cached) image for `url`.
    ///
    /// Multiple concurrent callers for the same URL share a single network Task.
    /// Cancellation is reference-counted: the shared Task is cancelled only when
    /// the last remaining waiter requests cancellation via `cancelFetch(for:)`.
    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        // Increment waiter count before suspending.
        waiters[url, default: 0] += 1

        defer {
            // Decrement on every exit path (return or cancellation).
            if let count = waiters[url] {
                if count <= 1 {
                    waiters.removeValue(forKey: url)
                } else {
                    waiters[url] = count - 1
                }
            }
        }

        if let existing = inFlight[url] {
            // Join the already-running fetch.
            return await existing.value
        }

        let capturedSession = session
        let cacheRef = cache
        let task = Task<NSImage?, Never> {
            guard !Task.isCancelled else { return nil }
            guard
                let (data, _) = try? await capturedSession.data(from: url),
                !Task.isCancelled,
                let image = NSImage(data: data)
            else { return nil }

            if !Task.isCancelled {
                cacheRef.setObject(image, forKey: url as NSURL)
            }
            return Task.isCancelled ? nil : image
        }

        inFlight[url] = task
        defer { inFlight.removeValue(forKey: url) }
        return await task.value
    }

    /// Cancel any in-flight fetch for `url` only when this is the last waiter.
    ///
    /// Call this from the view's cancellation hook (e.g. `withTaskCancellationHandler`
    /// `onCancel` block) while the corresponding `image(for:)` call is still in flight
    /// (i.e. the waiter count has not yet been decremented via `defer`).  If this is
    /// the only remaining waiter (`remaining == 1`), the shared Task is cancelled and
    /// removed.  If other waiters are still present, the Task is left running.
    func cancelFetch(for url: URL) {
        let remaining = waiters[url] ?? 0
        if remaining <= 1 {
            // Only this waiter (or none) — safe to cancel the shared Task.
            inFlight[url]?.cancel()
            inFlight.removeValue(forKey: url)
            waiters.removeValue(forKey: url)
        }
        // else: other waiters remain — leave the Task running.
    }

    /// Whether a fetch is currently in-flight for `url` (used in tests).
    func hasFetch(for url: URL) -> Bool {
        inFlight[url] != nil
    }

    /// Reset all state (used in tests to start from a clean slate).
    func reset() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        waiters.removeAll()
        cache.removeAllObjects()
    }
}

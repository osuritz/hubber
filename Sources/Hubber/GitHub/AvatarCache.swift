import AppKit
import Foundation

@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    /// Fetch (or return cached) image for `url`.
    ///
    /// Returns `(image, task)` where `task` is the in-flight `Task` that the caller
    /// should cancel when the requesting view disappears. If the image was already
    /// cached, `task` is `nil`.
    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        if let existing = inFlight[url] {
            // Join the already-running fetch; if *our* caller cancels, the shared task
            // keeps running for other waiters (correct behaviour).
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            // Honour cancellation before even starting the network request.
            guard !Task.isCancelled else { return nil }
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                !Task.isCancelled,
                let image = NSImage(data: data)
            else { return nil }

            // Only store in cache if the task wasn't cancelled mid-flight.
            if !Task.isCancelled {
                cache.setObject(image, forKey: url as NSURL)
            }
            return Task.isCancelled ? nil : image
        }

        inFlight[url] = task
        defer { inFlight.removeValue(forKey: url) }
        return await task.value
    }

    // MARK: - Internal / Testing

    /// Cancel any in-flight fetch for the given URL and remove it from the registry.
    /// Used by callers (e.g. AvatarView's `.task`) to abort when a row disappears.
    func cancelFetch(for url: URL) {
        inFlight[url]?.cancel()
        inFlight.removeValue(forKey: url)
    }

    /// Whether a fetch is currently in-flight for `url` (used in tests).
    func hasFetch(for url: URL) -> Bool {
        inFlight[url] != nil
    }
}

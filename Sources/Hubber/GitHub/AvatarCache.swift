import AppKit
import Foundation

@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func image(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if let existing = inFlight[url] {
            return await existing.value
        }
        let task = Task<NSImage?, Never> {
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let image = NSImage(data: data)
            else { return nil }
            cache.setObject(image, forKey: url as NSURL)
            return image
        }
        inFlight[url] = task
        let result = await task.value
        inFlight.removeValue(forKey: url)
        return result
    }
}

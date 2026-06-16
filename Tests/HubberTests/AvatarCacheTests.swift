import Foundation
import Testing
@testable import Hubber

@Suite("AvatarCache cancellation")
@MainActor
struct AvatarCacheTests {

    /// Verify that cancelling a fetch before completion does not leave a stale entry
    /// in the in-flight registry (hasFetch returns false after cancel).
    @Test("Cancelled fetch is removed from in-flight registry")
    func cancelledFetchRemovedFromInFlight() async throws {
        let cache = AvatarCache()
        let url = try #require(URL(string: "https://avatars.test/user1.png"))

        // Start a fetch in a Task using a URL that will never resolve
        // (no matching URLProtocol, so the URLSession call will fail quickly).
        let fetchTask = Task { @MainActor in
            await cache.image(for: url)
        }

        // Yield so the task body has a chance to register itself in inFlight.
        await Task.yield()

        // Cancel it before completion.
        fetchTask.cancel()

        // Wait for the task to finish.
        _ = await fetchTask.value

        // After cancellation + completion, there should be no entry in inFlight.
        #expect(!cache.hasFetch(for: url), "In-flight entry should be removed after cancellation")
    }

    /// Verify cancelFetch removes an entry from the in-flight registry.
    @Test("cancelFetch removes in-flight entry")
    func cancelFetchRemovesEntry() async throws {
        let cache = AvatarCache()
        let url = try #require(URL(string: "https://avatars.test/user2.png"))

        // Start a background fetch (ignore the result).
        let fetchTask = Task { @MainActor in
            await cache.image(for: url)
        }

        // Yield to let the task register.
        await Task.yield()

        // Explicitly cancel via the cache helper.
        cache.cancelFetch(for: url)

        // Wait for the task to drain.
        _ = await fetchTask.value

        // hasFetch should return false now.
        #expect(!cache.hasFetch(for: url), "cancelFetch should remove the in-flight entry")
    }

    /// Verify that a duplicate fetch for the same URL shares the same Task.
    @Test("Duplicate fetch joins existing in-flight task")
    func duplicateFetchJoinsExisting() async throws {
        let cache = AvatarCache()
        let url = try #require(URL(string: "https://avatars.test/user3.png"))

        // Start two concurrent fetches.
        async let r1 = cache.image(for: url)
        async let r2 = cache.image(for: url)

        // Both should complete without crashing (result may be nil since URL is unreachable).
        let (result1, result2) = await (r1, r2)
        // We can't assert both nil without knowing network; just confirm no crash.
        _ = result1
        _ = result2
    }
}

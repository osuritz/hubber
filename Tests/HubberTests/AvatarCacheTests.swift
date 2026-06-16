import Foundation
import Testing
@testable import Hubber

// MARK: - Helpers

/// Build an ephemeral URLSession backed by MockURLProtocol.
private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

/// Minimal 1×1 white PNG (valid NSImage data).
private let onePxPNG: Data = {
    // Split across lines to stay within the 120-char line-length limit.
    let b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQV"
        + "R42mP8/5+hHgAHggJ/PchI6QAAAABJRU5ErkJggg=="
    // swiftlint:disable:next force_unwrapping
    return Data(base64Encoded: b64)!
}()

// MARK: - AvatarCacheTests

/// Serialized so tests don't share MockURLProtocol static state concurrently.
@Suite("AvatarCache", .serialized)
@MainActor
struct AvatarCacheTests {

    // MARK: - Test 1: solo fetch cancelled before completion → cache NOT populated

    /// A single waiter that cancels before the (delayed) response arrives should
    /// NOT populate the NSCache.  The image should stay nil and the shared Task removed.
    ///
    /// Genuine cancellation is exercised because MockURLProtocol sleeps for 2 s on its
    /// URLSession thread, giving ample time for `cancelFetch` to cancel the shared Task
    /// before it can deliver a response.
    @Test("Solo fetch cancelled before completion does not populate cache")
    func soloCancelledFetchDoesNotPopulateCache() async throws {
        MockURLProtocol.reset()
        // 2-second delay ensures the cancel beats the response.
        MockURLProtocol.responseDelay = 2.0
        let url = try #require(URL(string: "https://avatars.test/user1.png"))
        MockURLProtocol.handler = { _ in
            guard
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ) else { throw URLError(.badServerResponse) }
            return (response, onePxPNG)
        }

        let session = makeMockSession()
        let cache = AvatarCache(session: session)

        // Launch the fetch so image(for:) registers in inFlight and starts URLSession.
        let fetchTask = Task { @MainActor in
            await cache.image(for: url)
        }

        // Yield multiple times to let the fetch Task execute up to its first suspension
        // (URLSession.data which suspends waiting for the network).
        for _ in 0..<5 {
            await Task.yield()
        }

        // Cancel: fetchTask.cancel() marks the outer wrapper as cancelled.
        // cancelFetch kills the shared network Task (sole waiter → remaining <= 1).
        fetchTask.cancel()
        cache.cancelFetch(for: url)

        // Await the wrapper — result is nil (cancelled or network error).
        _ = await fetchTask.value

        // After cancellation, hasFetch must be false.
        #expect(!cache.hasFetch(for: url), "In-flight entry should be gone after cancel")

        // Verify NSCache was not populated: use a fast (no-delay, failing handler) probe.
        MockURLProtocol.responseDelay = 0
        MockURLProtocol.handler = nil // fails immediately → only a cache hit returns non-nil
        let probeTask = Task { @MainActor in
            await cache.image(for: url)
        }
        let probeResult = await probeTask.value
        #expect(probeResult == nil, "NSCache must not be populated after a cancelled fetch")
    }

    // MARK: - Test 2: two waiters, cancel one → the other still resolves and cache IS populated

    /// Two concurrent waiters for the same URL share one Task.
    /// Cancelling one waiter via `cancelFetch` must NOT cancel the shared Task
    /// while the other waiter is still awaiting.  The surviving waiter must receive
    /// a non-nil image, and the NSCache must be populated afterward.
    ///
    /// The 2-second response delay guarantees the cancel arrives while the network
    /// Task is still in flight — if the response were delivered first, both waiters
    /// would have already completed and the cancellation would be a no-op, which
    /// would not exercise the ref-counting logic at all.
    @Test("Cancelling one of two waiters still resolves the other and populates cache")
    func cancelOneOfTwoWaitersPreservesOther() async throws {
        MockURLProtocol.reset()
        // Long enough that the cancel fires while the network Task is still running.
        MockURLProtocol.responseDelay = 2.0
        let url = try #require(URL(string: "https://avatars.test/user2.png"))
        MockURLProtocol.handler = { _ in
            guard
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ) else { throw URLError(.badServerResponse) }
            return (response, onePxPNG)
        }

        let session = makeMockSession()
        let cache = AvatarCache(session: session)

        // Waiter A — will be cancelled.
        let taskA = Task { @MainActor in
            await cache.image(for: url)
        }

        // Yield so taskA registers in inFlight and starts the URLSession request.
        for _ in 0..<5 {
            await Task.yield()
        }

        // Waiter B joins the same in-flight Task.
        let taskB = Task { @MainActor in
            await cache.image(for: url)
        }

        // Yield to let taskB increment the waiter count before we cancel.
        for _ in 0..<5 {
            await Task.yield()
        }

        // Cancel waiter A — but waiter B is still present (waiters[url] = 2 at this point).
        // cancelFetch must detect the surviving waiter and NOT kill the shared Task.
        taskA.cancel()
        cache.cancelFetch(for: url)

        // Waiter A resolves (cancelled → nil is acceptable).
        _ = await taskA.value

        // Waiter B must get a non-nil image because the network Task was NOT cancelled.
        let imageB = await taskB.value
        #expect(imageB != nil, "Surviving waiter should receive the image")

        // The NSCache should now contain the image.
        MockURLProtocol.responseDelay = 0
        MockURLProtocol.handler = nil // cut the network — only a cache hit returns non-nil
        let cachedTask = Task { @MainActor in
            await cache.image(for: url)
        }
        let cached = await cachedTask.value
        #expect(cached != nil, "NSCache should be populated after successful fetch")
    }
}

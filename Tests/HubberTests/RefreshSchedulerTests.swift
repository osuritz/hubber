import XCTest
@testable import Hubber

// MARK: - ControlledSleeper

/// An async sleeper whose sleep() genuinely suspends until the test resumes it
/// or the enclosing Task is cancelled.
///
/// Tests call `awaitParked()` to block until the scheduler has entered a sleep
/// (meaning the preceding refresh() has completed).  That removes all real-time
/// polling from the tests.
private actor ControlledSleeper {
    /// Intervals requested so far (for cadence assertions).
    private(set) var requestedIntervals: [TimeInterval] = []

    /// Waiters that want to know when we next park.
    private var parkWaiters: [CheckedContinuation<Void, Never>] = []

    /// The in-flight sleep continuation (nil when not sleeping).
    private var sleeping: CheckedContinuation<Void, Error>?

    /// Called by the scheduler loop instead of Task.sleep.
    func sleep(for interval: TimeInterval) async throws {
        requestedIntervals.append(interval)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                sleeping = cont
                // Wake all test waiters that are blocked in awaitParked().
                for waiter in parkWaiters {
                    waiter.resume()
                }
                parkWaiters.removeAll()
            }
        } onCancel: {
            Task { await self.cancelSleep() }
        }
    }

    /// Suspends the caller until the scheduler next calls sleep().
    func awaitParked() async {
        await withCheckedContinuation { cont in
            if sleeping != nil {
                // Already parked right now — resume immediately.
                cont.resume()
            } else {
                parkWaiters.append(cont)
            }
        }
    }

    /// Resumes the parked sleep so the scheduler can continue (used in stop tests).
    func resumeSleep() {
        sleeping?.resume()
        sleeping = nil
    }

    private func cancelSleep() {
        sleeping?.resume(throwing: CancellationError())
        sleeping = nil
    }
}

// MARK: - FakeIdleProvider

private struct FakeIdleProvider: MachineIdleProviding {
    var isIdle: Bool
}

// MARK: - Tests

@MainActor
final class RefreshSchedulerTests: XCTestCase {

    // MARK: - Cadence: background context → 300 s

    func testSchedulerRequestsIntervalFromCadenceFunction() async {
        let sleeper = ControlledSleeper()
        let ctx = RefreshContext() // background → 300 s
        var refreshCount = 0
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        scheduler.start(
            context: { ctx },
            refresh: { refreshCount += 1 }
        )

        // Block until the scheduler has done refresh #1 and is parked in sleep.
        await sleeper.awaitParked()

        let intervals = await sleeper.requestedIntervals
        XCTAssertFalse(intervals.isEmpty, "Expected at least one sleep interval")
        XCTAssertEqual(intervals.first ?? -1, 5 * 60, accuracy: 1)

        scheduler.stop()
    }

    // MARK: - Cadence: urgent SLO → 30 s

    func testSchedulerUsesUrgentIntervalForUrgentSLOContext() async {
        let sleeper = ControlledSleeper()
        let ctx = RefreshContext(hasUrgentSLO: true) // → 30 s
        var refreshCount = 0
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        scheduler.start(
            context: { ctx },
            refresh: { refreshCount += 1 }
        )

        await sleeper.awaitParked()

        let intervals = await sleeper.requestedIntervals
        XCTAssertEqual(intervals.first ?? -1, 30, accuracy: 1)

        scheduler.stop()
    }

    // MARK: - Cadence: idle + all-green → 15 × 60 s

    func testSchedulerUsesIdleAllGreenIntervalWhenIdleAndAllGreen() async {
        let sleeper = ControlledSleeper()
        // isMachineIdle is injected via FakeIdleProvider(isIdle: true).
        let ctx = RefreshContext(isAllGreen: true)
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: true),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        scheduler.start(context: { ctx }, refresh: {})

        await sleeper.awaitParked()

        let intervals = await sleeper.requestedIntervals
        XCTAssertEqual(
            intervals.first ?? -1,
            15 * 60,
            accuracy: 1,
            "Idle + all-green context should request the 15-minute cadence"
        )

        scheduler.stop()
    }

    // MARK: - reset() drives a second refresh

    func testResetTriggersImmediateRefresh() async {
        let sleeper = ControlledSleeper()
        var refreshCount = 0
        let ctx = RefreshContext()
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        scheduler.start(
            context: { ctx },
            refresh: { refreshCount += 1 }
        )

        // Await "parked after refresh #1"
        await sleeper.awaitParked()
        XCTAssertEqual(refreshCount, 1, "Expected exactly one refresh before first sleep")

        // reset() cancels the in-flight sleep → loop re-enters refresh() immediately.
        scheduler.reset()

        // Await "parked after refresh #2"  — proves reset() caused the refresh.
        await sleeper.awaitParked()
        XCTAssertGreaterThanOrEqual(refreshCount, 2, "reset() must drive a second refresh")

        scheduler.stop()
    }

    // MARK: - stop() halts the scheduler

    func testStopHaltsScheduler() async {
        let sleeper = ControlledSleeper()
        var refreshCount = 0
        let ctx = RefreshContext()
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        scheduler.start(
            context: { ctx },
            refresh: { refreshCount += 1 }
        )

        // Park after refresh #1.
        await sleeper.awaitParked()
        let countBeforeStop = refreshCount

        // stop() cancels the task; the sleep continuation throws CancellationError.
        scheduler.stop()

        // Let cancellation propagate.
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(refreshCount, countBeforeStop, "No refreshes should happen after stop()")
    }
}

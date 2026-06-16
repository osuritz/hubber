import XCTest
@testable import Hubber

/// A fake sleep that records requested intervals and can be cancelled immediately.
private actor FakeSleeper {
    private(set) var requestedIntervals: [TimeInterval] = []
    var shouldCancelOnNext = false
    var sleepCount = 0
    var maxSleeps: Int

    init(maxSleeps: Int = 3) {
        self.maxSleeps = maxSleeps
    }

    func sleep(for interval: TimeInterval) async throws {
        sleepCount += 1
        requestedIntervals.append(interval)
        if sleepCount >= maxSleeps || shouldCancelOnNext {
            // Simulate cancellation so the loop terminates in tests
            try Task.checkCancellation()
            throw CancellationError()
        }
    }
}

private struct FakeIdleProvider: MachineIdleProviding {
    var isIdle: Bool
}

@MainActor
final class RefreshSchedulerTests: XCTestCase {
    func testSchedulerRequestsIntervalFromCadenceFunction() async {
        let sleeper = FakeSleeper(maxSleeps: 1)
        var refreshCount = 0
        let ctx = RefreshContext() // background → 300s
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        let exp = expectation(description: "first refresh + sleep")
        scheduler.start(
            context: { ctx },
            refresh: {
                refreshCount += 1
                if refreshCount == 1 { exp.fulfill() }
            }
        )

        await fulfillment(of: [exp], timeout: 2)
        scheduler.stop()

        let intervals = await sleeper.requestedIntervals
        XCTAssertFalse(intervals.isEmpty, "Expected at least one sleep interval")
        XCTAssertEqual(intervals.first ?? -1, 5 * 60, accuracy: 1)
    }

    func testSchedulerUsesUrgentIntervalForUrgentSLOContext() async {
        let sleeper = FakeSleeper(maxSleeps: 1)
        var refreshCount = 0
        let ctx = RefreshContext(hasUrgentSLO: true) // → 30s
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        let exp = expectation(description: "first refresh")
        scheduler.start(
            context: { ctx },
            refresh: {
                refreshCount += 1
                if refreshCount == 1 { exp.fulfill() }
            }
        )

        await fulfillment(of: [exp], timeout: 2)
        scheduler.stop()

        let intervals = await sleeper.requestedIntervals
        XCTAssertEqual(intervals.first ?? -1, 30, accuracy: 1)
    }

    func testResetTriggersImmediateRefresh() async throws {
        var refreshCount = 0
        let sleeper = FakeSleeper(maxSleeps: 10)
        let ctx = RefreshContext()

        // Use a continuation to control when the scheduler may proceed after reset
        let resetExp = expectation(description: "refresh after reset")
        resetExp.expectedFulfillmentCount = 2 // initial + post-reset

        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in
                try await sleeper.sleep(for: interval)
            }
        )

        scheduler.start(
            context: { ctx },
            refresh: {
                refreshCount += 1
                if refreshCount <= 2 { resetExp.fulfill() }
            }
        )

        // Wait briefly for initial refresh, then reset
        try await Task.sleep(for: .milliseconds(50))
        scheduler.reset()

        await fulfillment(of: [resetExp], timeout: 3)
        scheduler.stop()

        XCTAssertGreaterThanOrEqual(refreshCount, 2, "Expected at least initial + post-reset refresh")
    }

    func testStopHaltsScheduler() async throws {
        var refreshCount = 0
        let sleeper = FakeSleeper(maxSleeps: 100) // won't block
        let ctx = RefreshContext()

        let firstRefreshExp = expectation(description: "first refresh")
        let scheduler = RefreshScheduler(
            idle: FakeIdleProvider(isIdle: false),
            sleep: { interval in try await sleeper.sleep(for: interval) }
        )

        scheduler.start(
            context: { ctx },
            refresh: {
                refreshCount += 1
                if refreshCount == 1 { firstRefreshExp.fulfill() }
            }
        )

        await fulfillment(of: [firstRefreshExp], timeout: 2)
        scheduler.stop()

        let countAfterStop = refreshCount
        // Give a short window to check no new refreshes happen
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(refreshCount, countAfterStop, "No refreshes should happen after stop")
    }
}

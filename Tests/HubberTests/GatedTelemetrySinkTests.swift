import Foundation
import XCTest
@testable import Hubber

final class GatedTelemetrySinkTests: XCTestCase {
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int {
            lock.withLock { _count }
        }

        func increment() {
            lock.withLock { _count += 1 }
        }
    }

    func testDisabledDoesNotForward() {
        let spy = SpyTelemetrySink()
        let sut = GatedTelemetrySink(enabled: false, underlying: spy, initializeSDK: {})
        sut.send("session.opened", [:])
        XCTAssertEqual(spy.calls.count, 0)
    }

    func testEnabledForwards() {
        let spy = SpyTelemetrySink()
        let sut = GatedTelemetrySink(enabled: true, underlying: spy, initializeSDK: {})
        sut.send("session.opened", [:])
        XCTAssertEqual(spy.calls.count, 1)
        XCTAssertEqual(spy.calls[0].event, "session.opened")
    }

    func testDisabledNeverInitializes() {
        let counter = CallCounter()
        let sut = GatedTelemetrySink(
            enabled: false,
            underlying: SpyTelemetrySink(),
            initializeSDK: { counter.increment() }
        )
        sut.send("a", [:])
        sut.send("b", [:])
        XCTAssertEqual(counter.count, 0)
    }

    func testInitializesOnceBeforeFirstForward() {
        let counter = CallCounter()
        let sut = GatedTelemetrySink(
            enabled: true,
            underlying: SpyTelemetrySink(),
            initializeSDK: { counter.increment() }
        )
        sut.send("a", [:])
        sut.send("b", [:])
        sut.send("c", [:])
        XCTAssertEqual(counter.count, 1)
    }

    func testSetEnabledStopsAndResumesLive() {
        let spy = SpyTelemetrySink()
        let sut = GatedTelemetrySink(enabled: true, underlying: spy, initializeSDK: {})
        sut.send("one", [:])
        sut.setEnabled(false)
        sut.send("two", [:])
        sut.setEnabled(true)
        sut.send("three", [:])
        XCTAssertEqual(spy.calls.map(\.event), ["one", "three"])
    }

    func testConcurrentSendsInitializeExactlyOnceAndNeverForwardBeforeInit() {
        final class OrderingSink: TelemetrySink, @unchecked Sendable {
            private let lock = NSLock()
            private var _sawForwardBeforeInit = false
            private let isInited: @Sendable () -> Bool
            init(isInited: @escaping @Sendable () -> Bool) {
                self.isInited = isInited
            }

            var sawForwardBeforeInit: Bool {
                lock.withLock { _sawForwardBeforeInit }
            }

            func send(_ event: String, _ params: [String: String]) {
                if !isInited() { lock.withLock { _sawForwardBeforeInit = true } }
            }
        }
        final class InitFlag: @unchecked Sendable {
            private let lock = NSLock()
            private var _value = false
            var value: Bool {
                lock.withLock { _value }
            }

            func set() {
                lock.withLock { _value = true }
            }
        }
        let counter = CallCounter()
        let initFlag = InitFlag()
        let sink = OrderingSink(isInited: { initFlag.value })
        let sut = GatedTelemetrySink(enabled: true, underlying: sink, initializeSDK: {
            counter.increment()
            initFlag.set()
        })
        DispatchQueue.concurrentPerform(iterations: 200) { _ in sut.send("e", [:]) }
        XCTAssertEqual(counter.count, 1, "SDK must initialize exactly once under concurrent sends")
        XCTAssertFalse(sink.sawForwardBeforeInit, "no send may be forwarded before initialization")
    }
}

//
//  ThrottlerTests.swift
//  MoltenTests
//
//  Regression coverage for deferred-fixes §3.1: the throttler must be a
//  leading+trailing throttle with a fixed window, not a trailing-edge
//  debounce. A continuous stream of calls must still flush every `delay`
//  seconds instead of waiting for a pause.
//

import XCTest
@testable import Molten

/// Locked counter so test closures can be formed in @Sendable contexts
/// without capturing mutable locals.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func increment() {
        lock.lock(); value += 1; lock.unlock()
    }
}

final class ThrottlerTests: XCTestCase {

    /// Spin the main run loop so blocks dispatched to .main can execute.
    private func spin(_ seconds: TimeInterval) {
        let exp = expectation(description: "spin \(seconds)s")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 2)
    }

    func testLeadingEdgeRunsImmediately() {
        let throttler = Throttler(delay: 0.3)
        let counter = Counter()
        let ran = expectation(description: "leading flush")

        throttler.throttle {
            counter.increment()
            ran.fulfill()
        }

        // Well under the 0.3s window: only a leading edge can satisfy this.
        wait(for: [ran], timeout: 0.2)
        XCTAssertEqual(counter.count, 1)
    }

    func testSingleCallDoesNotDoubleFire() {
        let throttler = Throttler(delay: 0.1)
        let counter = Counter()

        throttler.throttle { counter.increment() }
        spin(0.35)

        XCTAssertEqual(counter.count, 1, "A lone call must not also schedule a trailing flush")
    }

    func testBurstCoalescesToLeadingPlusOneTrailing() {
        let throttler = Throttler(delay: 0.15)
        let counter = Counter()

        for _ in 0..<5 {
            throttler.throttle { counter.increment() }
        }
        spin(0.5)

        XCTAssertEqual(counter.count, 2, "Burst should produce one leading and one trailing flush")
    }

    func testContinuousStreamFlushesAtFixedCadence() {
        // The old debounce rescheduled on every call, so calls every 20ms
        // with a 100ms window produced ~2 flushes total (leading + final
        // trailing). A real throttle flushes roughly every window: >= 3.
        let throttler = Throttler(delay: 0.1)
        let counter = Counter()
        let enough = expectation(description: "at least 3 flushes during continuous calls")
        // The driver may land one more flush before it sees the stop flag.
        enough.assertForOverFulfill = false

        Task.detached {
            for _ in 0..<22 {
                if counter.count >= 3 { break }
                throttler.throttle {
                    counter.increment()
                    if counter.count >= 3 { enough.fulfill() }
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }

        wait(for: [enough], timeout: 3)
    }

    func testCancelDropsPendingTrailingFlush() {
        let throttler = Throttler(delay: 0.2)
        let counter = Counter()

        throttler.throttle { counter.increment() } // leading
        throttler.throttle { counter.increment() } // schedules trailing
        throttler.cancel()
        spin(0.5)

        XCTAssertEqual(counter.count, 1, "cancel() must drop the pending trailing flush")
    }

    func testLatestBlockWins() {
        let throttler = Throttler(delay: 0.1)
        let counter = Counter()
        let secondBlockRan = Counter()

        throttler.throttle { counter.increment() }
        throttler.throttle {
            counter.increment()
            secondBlockRan.increment()
        }
        spin(0.4)

        // Leading ran block 1; the trailing slot must have been refreshed
        // to block 2 (if it still held block 1, secondBlockRan would be 0).
        XCTAssertEqual(counter.count, 2)
        XCTAssertEqual(secondBlockRan.count, 1, "The trailing flush must run the most recent block")
    }
}
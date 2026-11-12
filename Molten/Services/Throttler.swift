//
//  Throttler.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 29/12/2023.
//

import Foundation

/// Leading + trailing throttle with a fixed window.
///
/// The first call after a quiet period runs immediately (leading edge).
/// Calls inside the window coalesce into a single flush anchored to the
/// window's end (`lastRun + delay`) — the pending flush is NOT rescheduled
/// per call, so a continuous stream still flushes every `delay` seconds.
///
/// The previous implementation cancelled and rescheduled on every call,
/// which made it a trailing-edge debounce: with tokens arriving faster than
/// `delay`, the flush kept being pushed back and the UI only updated when
/// generation paused or finished (deferred-fixes §3.1).
final class Throttler: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingWork: DispatchWorkItem?
    private var latestBlock: (() -> Void)?
    private var lastRun: Date = .distantPast
    private let queue: DispatchQueue
    private let delay: TimeInterval

    init(delay: TimeInterval, queue: DispatchQueue = DispatchQueue.main) {
        self.delay = delay
        self.queue = queue
    }

    func throttle(_ block: @escaping () -> Void) {
        lock.lock()
        latestBlock = block
        let now = Date()

        if now.timeIntervalSince(lastRun) >= delay {
            // Window elapsed — leading edge. Supersede any pending flush.
            pendingWork?.cancel()
            pendingWork = nil
            lastRun = now
            // Safe by construction: the block is only ever executed on
            // `queue`, and callers confine their state to that queue too.
            nonisolated(unsafe) let work = latestBlock
            latestBlock = nil
            lock.unlock()
            queue.async { work?() }
        } else if pendingWork == nil {
            // Inside the window — schedule exactly one trailing flush at the
            // window end. Later calls only refresh the block, never the date.
            let item = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                self.pendingWork = nil
                self.lastRun = Date()
                let work = self.latestBlock
                self.latestBlock = nil
                self.lock.unlock()
                work?()
            }
            pendingWork = item
            let wait = max(0, lastRun.addingTimeInterval(delay).timeIntervalSince(now))
            lock.unlock()
            queue.asyncAfter(deadline: .now() + wait, execute: item)
        } else {
            lock.unlock()
        }
    }

    /// Drop any pending trailing flush. Callers that flush their buffer
    /// themselves (stop / error / new request) use this so a stale flush
    /// can't fire into the next stream.
    func cancel() {
        lock.lock()
        pendingWork?.cancel()
        pendingWork = nil
        latestBlock = nil
        lock.unlock()
    }
}
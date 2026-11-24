//
//  KnowledgeBackgroundTask.swift
//  Molten
//
//  Molten 2.0 — M5, K-P6. iOS long jobs use BGContinuedProcessingTask,
//  started only by a user action (Process now / Add files). Output is saved
//  per file and per stage, so finished work is never lost if the system
//  cancels the task (app swiped away).
//

#if os(iOS)
import Foundation
import BackgroundTasks

enum KnowledgeBackgroundTask {
    static let identifier = "com.ondemandworld.molten.knowledge.processing"

    // The processing task and completion flag are touched from the launch
    // handler, the expiration handler, and the task itself (arbitrary
    // threads) — guard them with a lock. Completing a BGTask twice is a
    // programmer error, so completion must go through completeOnce
    // (review 2026-11-24).
    private static let stateLock = NSLock()
    private nonisolated(unsafe) static var processingTask: Task<Void, Never>?
    private nonisolated(unsafe) static var completed = false

    private static func completeOnce(_ task: BGTask, success: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !completed else { return }
        completed = true
        task.setTaskCompleted(success: success)
    }

    /// Register at launch (before the end of application(_:didFinishLaunching…)).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            stateLock.lock()
            completed = false
            stateLock.unlock()

            continued.expirationHandler = {
                // Per-file/per-stage outputs are already persisted (K-D3).
                // Cancel the work so nothing keeps running (or completes the
                // task a second time) after the system reclaimed it.
                stateLock.lock()
                let running = processingTask
                stateLock.unlock()
                running?.cancel()
                completeOnce(continued, success: false)
            }
            let work = Task {
                for base in await KnowledgeStore.shared.bases() {
                    if Task.isCancelled { break }
                    try? await KnowledgeIndexer.shared.scan(base: base, force: true)
                }
                completeOnce(continued, success: !Task.isCancelled)
            }
            stateLock.lock()
            processingTask = work
            stateLock.unlock()
        }
    }

    /// Submit after a user action (K-P6).
    static func schedule() {
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Indexing knowledge",
            subtitle: "Processing your documents")
        try? BGTaskScheduler.shared.submit(request)
    }
}
#endif

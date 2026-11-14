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

    /// Register at launch (before the end of application(_:didFinishLaunching…)).
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            continued.expirationHandler = {
                // Per-file/per-stage outputs are already persisted (K-D3).
                continued.setTaskCompleted(success: false)
            }
            Task {
                for base in await KnowledgeStore.shared.bases() {
                    try? await KnowledgeIndexer.shared.scan(base: base, force: true)
                }
                continued.setTaskCompleted(success: true)
            }
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

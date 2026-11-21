//
//  KnowledgeContainer.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge")

/// K-S1/K-S5: one shared iCloud container; identical local layout fallback.
/// M4 implements migration and coordinated access.
enum KnowledgeContainer {
    /// K-S1: identical across app, Share Extension (M5) and test targets.
    static let expectedContainerID = "iCloud.DVGF44TKAX.com.ondemandworld.molten"

    /// iCloud container root, or nil when signed out / unavailable.
    static func iCloudRoot() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: expectedContainerID)
    }

    /// K-S5 local fallback root (same layout as the iCloud container).
    static func localRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Molten/LocalKnowledge", isDirectory: true)
    }

    /// M3 uses the local layout; M4 switches Plus users to the iCloud root.
    static func activeRoot() -> URL {
        localRoot()
    }

    /// K-S3: each top-level folder under Documents/ is one knowledge base.
    static func documentsRoot() -> URL {
        activeRoot().appendingPathComponent("Documents", isDirectory: true)
    }

    /// K-D layout: hidden, synced index area.
    static func indexRoot() -> URL {
        activeRoot().appendingPathComponent("Index", isDirectory: true)
    }

    static func textDirectory() -> URL {
        indexRoot().appendingPathComponent("text", isDirectory: true)
    }

    static func vectorsDirectory(profile: String) -> URL {
        indexRoot().appendingPathComponent("vectors/\(profile)", isDirectory: true)
    }

    static func baseDirectory(_ base: BaseID) -> URL {
        documentsRoot().appendingPathComponent(base, isDirectory: true)
    }

    /// K-S6: DEBUG launch check — warn when the container does not resolve
    /// to the expected identifier. Called from ApplicationEntry.task.
    #if DEBUG
    static func debugCheck() {
        if let url = iCloudRoot() {
            if url.lastPathComponent != expectedContainerID {
                logger.warning("K-S6: resolved container \(url.lastPathComponent, privacy: .public) != expected \(expectedContainerID, privacy: .public)")
            }
        } else {
            logger.info("K-S6: iCloud container unavailable (signed out or not provisioned) — Knowledge uses the local layout (K-S5)")
        }
    }
    #endif
}

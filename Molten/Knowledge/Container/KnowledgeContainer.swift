//
//  KnowledgeContainer.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation
import OSLog

/// A knowledge base identifier (top-level folder name under Documents/).
typealias BaseID = String

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

    // M4: resolved root cache. Plus + iCloud available → the shared iCloud
    // container; otherwise the identical local layout (K-S5). Refreshed at
    // launch and after entitlement changes via resolveRoot().
    private static let rootLock = NSLock()
    private static var cachedRoot: URL?

    static func activeRoot() -> URL {
        rootLock.lock()
        defer { rootLock.unlock() }
        return cachedRoot ?? localRoot()
    }

    static func resolveRoot() async {
        let plus = await EntitlementManager.shared.allows(.iCloudKnowledge)
        let root = plus ? (iCloudRoot() ?? localRoot()) : localRoot()
        setCachedRoot(root)
    }

    private static func setCachedRoot(_ root: URL) {
        rootLock.lock()
        cachedRoot = root
        rootLock.unlock()
    }

    /// K-S5/A14: upgrading to Plus moves base folders and Index files into
    /// the iCloud container. Files are content-hash named, so nothing is
    /// reprocessed.
    static func migrateLocalToICloud() async throws {
        guard await EntitlementManager.shared.allows(.iCloudKnowledge),
              let iCloud = iCloudRoot() else { return }
        let local = localRoot()
        guard FileManager.default.fileExists(atPath: local.path) else { return }
        for area in ["Documents", "Index"] {
            let source = local.appendingPathComponent(area, isDirectory: true)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: source.path) else { continue }
            for entry in entries {
                let from = source.appendingPathComponent(entry)
                let to = iCloud.appendingPathComponent(area).appendingPathComponent(entry)
                if FileManager.default.fileExists(atPath: to.path) { continue }
                try CoordinatedIO.move(from: from, to: to)
            }
        }
        await resolveRoot()
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

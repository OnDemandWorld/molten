//
//  CoordinatedIO.swift
//  Molten
//
//  Molten 2.0 — M4, §7.4. All container reads/writes go through
//  NSFileCoordinator; cloud-only files are downloaded before reading;
//  .icloud placeholders and conflict versions are ignored (outputs are
//  deterministic, so any one copy is fine).
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge.io")

enum CoordinatedIO {
    /// True for iCloud placeholder files (" .name.icloud") and conflict copies.
    static func isPlaceholderOrConflict(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasSuffix(".icloud") { return true }
        if name.contains(" (") && name.contains("conflict") { return true }
        // Conflict copies like "name 2.ext" are handled by content addressing:
        // identical hashes mean identical outputs, duplicates are harmless.
        return false
    }

    /// Kick off download of a cloud-only item; never blocks the UI.
    static func downloadIfNeeded(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    static func isDownloaded(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values?.ubiquitousItemDownloadingStatus else { return true } // local file
        return status == .current
    }

    /// Coordinated read. Returns nil when the file is not yet downloaded.
    static func read(_ url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        if !isDownloaded(url) {
            downloadIfNeeded(url)
            return nil
        }
        var result: Data?
        var error: NSError?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readable in
            result = try? Data(contentsOf: readable)
        }
        if let error {
            logger.error("Coordinated read failed: \(error.localizedDescription, privacy: .public)")
        }
        return result
    }

    /// Coordinated write-once (K-D3): skips when the target already exists.
    static func writeOnce(_ data: Data, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writable in
            do {
                try data.write(to: writable, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let error { throw error }
        if let writeError { throw writeError }
    }

    /// Coordinated move (Free → Plus migration, K-S5).
    static func move(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var error: NSError?
        var moveError: Error?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: source, options: .forMoving,
                               writingItemAt: destination, options: .forReplacing,
                               error: &error) { src, dst in
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                moveError = error
            }
        }
        if let error { throw error }
        if let moveError { throw moveError }
    }
}

//
//  ShareImport.swift
//  Molten
//
//  Molten 2.0 — K-S4/K-U3. Shared logic for the iOS Share Extension:
//  write the shared file directly into the chosen base folder through the
//  iCloud container (no kept copy). Lives in the app target so it is unit
//  testable; the extension links the same sources.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge.share")

enum ShareImport {
    enum ShareError: Error { case noBase, writeFailed, invalidName }

    /// G3 (review 2026-11-24): base names become path components under
    /// Documents/. Reject anything that could escape the base layout
    /// ("..", "/"), hide the folder (leading "."), or break Finder/POSIX
    /// conventions. Returns the trimmed name, or nil when invalid.
    static func sanitizedBaseName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64,
              name != ".", name != "..",
              !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"), !name.contains(":")
        else { return nil }
        return name
    }

    /// K-S3: top-level folders under Documents/ are the bases.
    static func availableBases() -> [String] {
        let documents = KnowledgeContainer.documentsRoot()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: documents, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    static func createBase(_ name: String) throws {
        guard let clean = sanitizedBaseName(name) else { throw ShareError.invalidName }
        let dir = KnowledgeContainer.baseDirectory(clean)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// K-S4: write the file directly into the base folder. Content-hash
    /// naming downstream means duplicate shares never reprocess (G4).
    @discardableResult
    static func importFile(_ data: Data, fileName: String, intoBase base: String) throws -> URL {
        guard let clean = sanitizedBaseName(base) else { throw ShareError.noBase }
        let dir = KnowledgeContainer.baseDirectory(clean)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // File names are path components too: strip any directory parts.
        let leaf = URL(fileURLWithPath: fileName).lastPathComponent
        guard !leaf.isEmpty, leaf != ".", leaf != ".." else { throw ShareError.writeFailed }
        var destination = dir.appendingPathComponent(leaf)
        // Avoid clobbering an existing file with different content.
        if FileManager.default.fileExists(atPath: destination.path) {
            let stem = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            destination = dir.appendingPathComponent("\(stem)-\(UUID().uuidString.prefix(8)).\(ext)")
        }
        try CoordinatedIO.writeOnce(data, to: destination)
        logger.info("Shared file imported: \(destination.lastPathComponent, privacy: .public) into \(base, privacy: .public)")
        return destination
    }
}

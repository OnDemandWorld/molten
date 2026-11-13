//
//  HFSnapshotDownloader.swift
//  Molten
//
//  Molten 2.0 — M1 spike. K-E3: one-time model download at a pinned revision,
//  hash-verified, stored in Application Support/Molten/Models/ (excluded from
//  iCloud and backup). Uses only official huggingface.co endpoints (P1).
//

import Foundation
import CryptoKit
import MLXLMCommon
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge.download")

/// Minimal `Downloader` conformance against the official Hugging Face Hub.
/// Deliberately dependency-free (URLSession) for the M1 spike; M3 may swap in
/// the official swift-huggingface client without changing callers.
struct HFSnapshotDownloader: Downloader {
    /// K-E3 storage root: Application Support/Molten/Models/
    static var modelsRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Molten/Models", isDirectory: true)
    }

    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let rev = revision ?? "main"
        let dest = Self.modelsRoot
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent(rev, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        // K-E3: exclude model storage from iCloud/backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDest = dest
        try? mutableDest.setResourceValues(values)

        let files = try await Self.fileList(id: id, revision: rev)
        let wanted = files.filter { entry in
            patterns.isEmpty || patterns.contains { Self.glob($0, matches: entry.path) }
        }
        guard !wanted.isEmpty else {
            throw KnowledgeError.notImplemented("No files matched patterns \(patterns) for \(id)@\(rev)")
        }

        let progress = Progress(totalUnitCount: Int64(wanted.count))
        let observer = progress.observe(\.fractionCompleted) { p, _ in
            progressHandler(p)
        }
        defer { observer.invalidate() }

        for entry in wanted {
            let target = dest.appendingPathComponent(entry.path)
            if FileManager.default.fileExists(atPath: target.path),
               try Self.verify(file: target, expectedSHA256: entry.sha256) {
                progress.completedUnitCount += 1
                continue // cached and verified — never re-download (K-E3)
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let url = URL(string: "https://huggingface.co/\(id)/resolve/\(rev)/\(entry.path)")!
            let (tmp, _) = try await URLSession.shared.download(from: url)
            try FileManager.default.moveItem(at: tmp, to: target)
            guard try Self.verify(file: target, expectedSHA256: entry.sha256) else {
                throw KnowledgeError.notImplemented("Hash mismatch for \(entry.path) (K-E3)")
            }
            progress.completedUnitCount += 1
            logger.info("Downloaded \(entry.path, privacy: .public) (\(entry.size) bytes)")
        }
        return dest
    }

    // MARK: - Hub API

    struct FileEntry: Decodable {
        let path: String
        let size: Int
        let lfs: LFS?
        struct LFS: Decodable { let oid: String }
        var sha256: String? { lfs?.oid }
    }

    /// Official Hub tree API: https://huggingface.co/api/models/{id}/tree/{rev}
    static func fileList(id: String, revision: String) async throws -> [FileEntry] {
        var out: [FileEntry] = []
        var cursor: String? = nil
        repeat {
            var comps = URLComponents(string: "https://huggingface.co/api/models/\(id)/tree/\(revision)")!
            var items = [URLQueryItem(name: "recursive", value: "true")]
            if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            comps.queryItems = items
            let (data, response) = try await URLSession.shared.data(from: comps.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw KnowledgeError.notImplemented("Hub tree API failed for \(id)@\(revision)")
            }
            out.append(contentsOf: try JSONDecoder().decode([FileEntry].self, from: data))
            // Pagination: the Hub returns a Link header shaped like
            // `<url>; rel="next", <url>; rel="last"`. Entries are separated
            // by commas; the URL is the first ";"-segment of each entry and
            // the rel parameter lives in the later segments.
            cursor = nil
            if let http = response as? HTTPURLResponse,
               let link = http.value(forHTTPHeaderField: "Link") {
                for entry in link.split(separator: ",") {
                    let segments = entry.split(separator: ";")
                    guard segments.count >= 2,
                          segments[1...].contains(where: { $0.contains("rel=\"next\"") }) else { continue }
                    let raw = segments[0].trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
                    cursor = URLComponents(string: raw)?.queryItems?.first { $0.name == "cursor" }?.value
                    break
                }
            }
        } while cursor != nil
        return out.filter { $0.size > 0 || $0.lfs != nil }
    }

    static func verify(file: URL, expectedSHA256: String?) throws -> Bool {
        guard let expected = expectedSHA256 else { return true } // non-LFS: size-only trust
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined() == expected.lowercased()
    }

    /// Minimal glob: supports leading "*" and "*" anywhere (fnmatch-style).
    static func glob(_ pattern: String, matches name: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var remainder = Substring(name)
        for (i, part) in parts.enumerated() {
            if part.isEmpty { continue }
            if i == 0 {
                guard remainder.hasPrefix(part) else { return false }
                remainder = remainder.dropFirst(part.count)
            } else if i == parts.count - 1 {
                guard remainder.hasSuffix(part) else { return false }
                remainder = remainder.dropLast(part.count)
            } else {
                guard let r = remainder.range(of: part) else { return false }
                remainder = remainder[r.upperBound...]
            }
        }
        return true
    }
}

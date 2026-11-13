//
//  KnowledgeIndexer.swift
//  Molten
//
//  Molten 2.0 — M3 local pipeline (K-P1/K-P7/K-D3, K-S5 layout).
//  M4 adds iCloud coordination, M5 adds claims/heartbeats/best-device roles.
//  Each document is processed once: outputs are content-addressed by the
//  SHA-256 of the source bytes and skipped when they already exist (G4).
//

import Foundation
import CryptoKit
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge.indexer")

enum Stage: String, Codable, Sendable { case extract, embed }

enum IndexingError: Error {
    case unsupportedFile(String)
    case limitReached(String)
}

/// K-U5 Free limits: 1 base, 10 documents, local only, no OCR.
enum KnowledgeLimits {
    static let freeBaseCount = 1
    static let freeDocumentCount = 10

    static func canCreateBase(existing: Int, unlimited: Bool) -> Bool {
        unlimited || existing < freeBaseCount
    }

    static func canAddDocument(existing: Int, unlimited: Bool) -> Bool {
        unlimited || existing < freeDocumentCount
    }
}

actor KnowledgeIndexer {
    static let shared = KnowledgeIndexer()

    private let store: KnowledgeStore
    private let embeddings: EmbeddingService

    init(store: KnowledgeStore = .shared, embeddings: EmbeddingService = .shared) {
        self.store = store
        self.embeddings = embeddings
    }

    /// K-P3: iOS defers to a fresh Mac unless forced ("Process now").
    func shouldDefer() async -> Bool {
        let devices = await HeartbeatService.shared.devices()
        return DeviceRoles.shouldDeferToMac(devices: devices, letMacDoIt: DeviceRoles.letMacDoIt)
    }

    /// Scan a base folder and process every supported file (K-P7, local).
    func scan(base: BaseID, force: Bool = false) async throws {
        let deferring = await shouldDefer()
        if !force && deferring {
            logger.info("Deferring to Mac (K-P3); use Process now to override")
            return
        }
        let directory = KnowledgeContainer.baseDirectory(base)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return }

        let unlimited = await EntitlementManager.shared.allows(.unlimitedKnowledge)
        // Match the entitlement extractStage uses — hardcoding false here
        // would skip images even for Plus users with OCR.
        let ocrAllowed = await EntitlementManager.shared.allows(.ocr)
        var processed = await store.documentCount(base: base)

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard ExtractorFactory.extractor(for: url, ocrAllowed: ocrAllowed) != nil else { continue }
            if !KnowledgeLimits.canAddDocument(existing: processed, unlimited: unlimited) {
                logger.info("Free document limit reached for base \(base, privacy: .public)")
                break
            }
            do {
                // Only newly ingested documents count against the limit —
                // re-scanning already-indexed files must not consume quota.
                if try await process(file: url, base: base) {
                    processed += 1
                }
            } catch {
                logger.error("Indexing failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Extract → chunk → .mkt, then embed → .mkv when the model is ready.
    /// Existing outputs are never regenerated (K-D3, G4). Stages are claimed
    /// per K-P2 and gated by the device's stage policy (K-P4).
    /// Returns true when this call ingested a document new to the store.
    @discardableResult
    func process(file: URL, base: BaseID) async throws -> Bool {
        let hash = try Self.sha256(of: file)
        let isNew = !(await store.hasDocument(hash: hash))
        let profile = EmbeddingProfile.e5sV1
        let mktURL = KnowledgeContainer.textDirectory()
            .appendingPathComponent("\(hash).mkt")
        let mkvURL = KnowledgeContainer.vectorsDirectory(profile: profile.id)
            .appendingPathComponent("\(hash).mkv")
        let stages = DeviceRoles.allowedStages(policy: DeviceRoles.policy, isCharging: DeviceRoles.isCharging)
        // Shared instance: the K-P11 attempt counter must survive across
        // files and scans, not reset with every call.
        let claims = ClaimStore.shared

        if stages.contains(.extract), !FileManager.default.fileExists(atPath: mktURL.path) {
            guard await claims.tryClaim(hash: hash, stage: .extract) else {
                logger.info("Extract claimed by another device: \(hash, privacy: .public)")
                return false
            }
            do {
                try await extractStage(file: file, hash: hash, mktURL: mktURL)
                await claims.release(hash: hash, stage: .extract, failed: nil)
            } catch {
                await claims.release(hash: hash, stage: .extract, failed: error.localizedDescription)
                throw error
            }
        }
        try await store.ingest(mkt: mktURL, base: base, name: file.lastPathComponent)
        let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        await FileMapping.shared.update(path: file.path, entry: FileMapEntry(
            hash: hash, base: base, name: file.lastPathComponent, mtime: mtime))

        // Embed stage: skipped entirely until the model is ready (K-R2
        // keyword-only fallback keeps the text searchable meanwhile, A11).
        if stages.contains(.embed), await embeddings.isReady {
            guard await claims.tryClaim(hash: hash, stage: .embed) else { return isNew }
            do {
                if !FileManager.default.fileExists(atPath: mkvURL.path) {
                    let document = try MKTCodec.decode(Data(contentsOf: mktURL))
                    let vectors = try await embeddings.embed(passages: document.chunks.map(\.text))
                    let header = MKVHeader(
                        schema: 1,
                        sourceHash: hash,
                        profileID: profile.id,
                        modelRevision: profile.modelRevision,
                        dims: profile.dims,
                        count: vectors.count,
                        chunkerVersion: Chunker.chunkerVersion,
                        encryption: nil,
                        createdBy: DeviceIdentity.id,
                        createdAt: ISO8601DateFormatter().string(from: Date()))
                    try CoordinatedIO.writeOnce(MKVCodec.encode(header: header, vectors: vectors), to: mkvURL)
                }
                // K-E2/A6: only ingest vectors matching the active profile.
                let (header, _) = try MKVCodec.decode(Data(contentsOf: mkvURL))
                if ManifestStore.accepts(header: header, manifest: ManifestStore.loadOrCreate()) {
                    try await store.ingest(mkv: mkvURL)
                }
                await claims.release(hash: hash, stage: .embed, failed: nil)
            } catch {
                await claims.release(hash: hash, stage: .embed, failed: error.localizedDescription)
                throw error
            }
        }
        return isNew
    }

    private func extractStage(file: URL, hash: String, mktURL: URL) async throws {
        let profile = EmbeddingProfile.e5sV1
        let ocrAllowed = await EntitlementManager.shared.allows(.ocr)
        guard let extractor = ExtractorFactory.extractor(for: file, ocrAllowed: ocrAllowed) else {
            throw IndexingError.unsupportedFile(file.lastPathComponent)
        }
        let extracted = try await extractor.extract(from: file)
        let chunks = await Chunker.chunk(
            text: extracted.text,
            pages: extracted.pages,
            prefix: profile.passagePrefix,
            tokenCount: { [embeddings] text in await embeddings.countTokens(text) })
        let document = MKTDocument(
            schema: MKTDocument.currentSchema,
            sourceHash: hash,
            mime: Self.mimeType(for: file),
            extractorVersion: MKTDocument.extractorVersion,
            ocrUsed: extracted.ocrUsed,
            chunkerVersion: Chunker.chunkerVersion,
            pages: extracted.pages,
            chunks: chunks,
            encryption: nil,
            createdBy: DeviceIdentity.id,
            createdAt: ISO8601DateFormatter().string(from: Date()))
        try CoordinatedIO.writeOnce(MKTCodec.encode(document), to: mktURL)
    }

    // MARK: - Helpers

    /// Streamed SHA-256 of the source bytes (K-D3).
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    /// K-D3: write once, never edit; duplicate writes are harmless.
    static func writeOnce(_ data: Data, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "rtf": return "application/rtf"
        case "html", "htm": return "text/html"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "heic": return "image/heic"
        case "md", "markdown": return "text/markdown"
        default: return "text/plain"
        }
    }
}

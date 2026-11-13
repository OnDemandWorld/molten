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

    /// Scan a base folder and process every supported file (K-P7, local).
    func scan(base: BaseID) async throws {
        let directory = KnowledgeContainer.baseDirectory(base)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return }

        let unlimited = await EntitlementManager.shared.allows(.unlimitedKnowledge)
        var processed = await store.documentCount(base: base)

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            guard ExtractorFactory.extractor(for: url, ocrAllowed: false) != nil else { continue }
            if !KnowledgeLimits.canAddDocument(existing: processed, unlimited: unlimited) {
                logger.info("Free document limit reached for base \(base, privacy: .public)")
                break
            }
            do {
                try await process(file: url, base: base)
                processed += 1
            } catch {
                logger.error("Indexing failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Extract → chunk → .mkt, then embed → .mkv when the model is ready.
    /// Existing outputs are never regenerated (K-D3, G4).
    func process(file: URL, base: BaseID) async throws {
        let hash = try Self.sha256(of: file)
        let profile = EmbeddingProfile.e5sV1
        let mktURL = KnowledgeContainer.textDirectory()
            .appendingPathComponent("\(hash).mkt")
        let mkvURL = KnowledgeContainer.vectorsDirectory(profile: profile.id)
            .appendingPathComponent("\(hash).mkv")

        if !FileManager.default.fileExists(atPath: mktURL.path) {
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
            try Self.writeOnce(MKTCodec.encode(document), to: mktURL)
        }
        try await store.ingest(mkt: mktURL, base: base, name: file.lastPathComponent)

        // Embed stage: skipped entirely until the model is ready (K-R2
        // keyword-only fallback keeps the text searchable meanwhile, A11).
        if await embeddings.isReady {
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
                try Self.writeOnce(MKVCodec.encode(header: header, vectors: vectors), to: mkvURL)
            }
            try await store.ingest(mkv: mkvURL)
        }
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

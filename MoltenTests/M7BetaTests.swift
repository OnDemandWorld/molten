//
//  M7BetaTests.swift
//  MoltenTests
//
//  Molten 2.0 — M7: A12 profile-migration simulation (re-embed from .mkt
//  only, search keeps working) and performance acceptance A1/A4 (gated by
//  the MOLTEN_PERF marker; numbers recorded in docs/SPIKE.md).
//

import Foundation
import Testing
import PDFKit
import CoreText
#if os(macOS)
import AppKit
#endif
@testable import Molten

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("m7-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
private var perfEnabled: Bool {
    FileManager.default.fileExists(atPath:
        repoRoot.appendingPathComponent("build/session/MOLTEN_PERF").path)
}

@Suite("M7 — Profile migration (K-E4/A12)")
struct ProfileMigrationTests {
    private let testProfile = EmbeddingProfile(
        id: "test-profile", modelID: "intfloat/multilingual-e5-small",
        modelRevision: "test-rev", dims: 384, pooling: "mean", normalize: true,
        queryPrefix: "query: ", passagePrefix: "passage: ", maxTokens: 512)

    @Test func planComputesCoverage() {
        let plan = ProfileMigration.plan(mktHashes: ["a", "b", "c"], newProfileMKVHashes: ["a"])
        #expect(plan.needsEmbedding == ["b", "c"])
        #expect(plan.alreadyCovered == ["a"])
        #expect(abs(plan.coverage - 1.0 / 3.0) < 0.001)
        let full = ProfileMigration.plan(mktHashes: ["a"], newProfileMKVHashes: ["a"])
        #expect(full.coverage == 1.0)
    }

    @Test func manifestTransitions() {
        var manifest = Manifest.initial(deviceID: "test")
        ProfileMigration.beginMigration(manifest: &manifest, newProfile: testProfile)
        #expect(manifest.migratingProfile == "test-profile")
        #expect(manifest.activeProfile == "e5s-v1") // old profile keeps serving
        // Not complete until 100% coverage.
        #expect(!ProfileMigration.completeMigration(manifest: &manifest, coverage: 0.99))
        #expect(manifest.activeProfile == "e5s-v1")
        #expect(ProfileMigration.completeMigration(manifest: &manifest, coverage: 1.0))
        #expect(manifest.activeProfile == "test-profile")
        #expect(manifest.migratingProfile == nil)
    }

    @Test func reembedSkipsExistingOutputWithoutModel() async throws {
        // A12: existing new-profile outputs are never regenerated; the skip
        // path requires no model and no extraction.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let text = dir.appendingPathComponent("text", isDirectory: true)
        let vectors = dir.appendingPathComponent("vectors", isDirectory: true)
        try FileManager.default.createDirectory(at: text, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vectors, withIntermediateDirectories: true)
        let mkv = vectors.appendingPathComponent("h.mkv")
        try Data("existing".utf8).write(to: mkv)
        // No .mkt exists — if reembed tried to extract, it would throw.
        try await ProfileMigration.reembed(hash: "h", profile: testProfile,
                                           textDirectory: text, vectorsDirectory: vectors,
                                           embeddings: EmbeddingService())
        #expect(try Data(contentsOf: mkv) == Data("existing".utf8))
    }

    @Test func migrationNeverTouchesMKT() async throws {
        // A12: .mkt files are inputs only — migration reads, never writes.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let document = MKTDocument(
            schema: 1, sourceHash: "h", mime: "text/plain", extractorVersion: 1,
            ocrUsed: true, chunkerVersion: 1,
            pages: [MKTPage(index: 1, charStart: 0, charEnd: 10)],
            chunks: [MKTChunk(i: 0, text: "chunk", page: 1, charStart: 0, charEnd: 5, tokens: 1)],
            encryption: nil, createdBy: "t", createdAt: "t")
        let mkt = dir.appendingPathComponent("h.mkt")
        let original = try MKTCodec.encode(document)
        try original.write(to: mkt)
        let before = try FileManager.default.attributesOfItem(atPath: mkt.path)[.modificationDate] as? Date
        // Plan + manifest transitions must not modify the .mkt.
        _ = ProfileMigration.plan(mktHashes: ["h"], newProfileMKVHashes: [])
        var manifest = Manifest.initial(deviceID: "t")
        ProfileMigration.beginMigration(manifest: &manifest, newProfile: testProfile)
        let after = try FileManager.default.attributesOfItem(atPath: mkt.path)[.modificationDate] as? Date
        #expect(before == after)
        #expect(try Data(contentsOf: mkt) == original)
    }
}

#if os(macOS)
private typealias PlatformFont = NSFont
#else
private typealias PlatformFont = UIFont
#endif

/// Runs on macOS and the iOS Simulator — A1/A4 do not require MLX
/// (PDFKit + Chunker + Accelerate). See docs/REMAINING_ISSUES.md.
@Suite("M7 — Performance acceptance (A1/A4)", .enabled(if: perfEnabled))
struct PerformanceAcceptanceTests {
    @Test func a1HundredPagePDFUnder60s() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("hundred.pdf")

        // Generate a 100-page text PDF.
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data)!
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        for page in 0..<100 {
            ctx.beginPDFPage(nil)
            for line in 0..<30 {
                let text = "Page \(page + 1) line \(line + 1): the quick brown fox jumps over the lazy dog near the river bank."
                let attr = NSAttributedString(string: text, attributes: [.font: PlatformFont.systemFont(ofSize: 11)])
                let ctLine = CTLineCreateWithAttributedString(attr)
                ctx.textPosition = CGPoint(x: 40, y: 740 - CGFloat(line) * 22)
                CTLineDraw(ctLine, ctx)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        try data.write(to: file)

        let start = Date()
        let extractor = PDFExtractor(ocrAllowed: false)
        let extracted = try await extractor.extract(from: file)
        let chunks = await Chunker.chunk(text: extracted.text, pages: extracted.pages,
                                         prefix: "passage: ", tokenCount: { max(1, $0.count / 4) })
        let elapsed = Date().timeIntervalSince(start)
        print("A1: 100-page PDF extract+chunk \(String(format: "%.2f", elapsed))s, \(chunks.count) chunks")
        #expect(extracted.pages.count == 100)
        #expect(chunks.count > 50)
        #expect(elapsed < 60)
    }

    @Test func a4TwentyThousandChunksSearchUnder200ms() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KnowledgeStore(directory: dir)

        // 100 documents × 200 chunks = 20,000 chunks, with vectors.
        for doc in 0..<100 {
            let hash = String(format: "%064x", doc)
            let chunks = (0..<200).map { i in
                MKTChunk(i: i, text: "Document \(doc) chunk \(i) about topic \(i % 25) with searchable content keyword\(doc % 10).",
                         page: 1, charStart: i * 100, charEnd: i * 100 + 90, tokens: 20)
            }
            let document = MKTDocument(schema: 1, sourceHash: hash, mime: "text/plain",
                                       extractorVersion: 1, ocrUsed: false, chunkerVersion: 1,
                                       pages: [MKTPage(index: 1, charStart: 0, charEnd: 20000)],
                                       chunks: chunks, encryption: nil, createdBy: "t", createdAt: "t")
            let mkt = dir.appendingPathComponent("\(hash).mkt")
            try MKTCodec.encode(document).write(to: mkt)
            try await store.ingest(mkt: mkt, base: "Perf", name: "doc\(doc).txt")

            var vectors: [[Float]] = []
            for i in 0..<200 {
                var v = [Float](repeating: 0, count: 384)
                v[(doc + i) % 384] = 1
                vectors.append(v)
            }
            let header = MKVHeader(schema: 1, sourceHash: hash,
                                   profileID: EmbeddingProfile.e5sV1.id,
                                   modelRevision: EmbeddingProfile.e5sV1.modelRevision,
                                   dims: 384, count: 200, chunkerVersion: 1,
                                   encryption: nil, createdBy: "t", createdAt: "t")
            let mkv = dir.appendingPathComponent("\(hash).mkv")
            try MKVCodec.encode(header: header, vectors: vectors).write(to: mkv)
            try await store.ingest(mkv: mkv)
        }

        var query = [Float](repeating: 0, count: 384)
        query[42] = 1
        let start = Date()
        let hits = await store.search("keyword7", queryVector: query, base: "Perf", limit: 8)
        let elapsed = Date().timeIntervalSince(start)
        print("A4: hybrid search over 20,000 chunks \(String(format: "%.1f", elapsed * 1000))ms, \(hits.count) hits")
        #expect(!hits.isEmpty)
        #expect(elapsed < 0.2)
    }
}

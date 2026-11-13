//
//  M3KnowledgeTests.swift
//  MoltenTests
//
//  Molten 2.0 — M3 exit criteria: codec round-trip tests, chunker boundary
//  tests, retrieval tests on fixture documents. A1/A4/A7/A11 coverage where
//  runnable without the embedding model (model-dependent paths are gated).
//

import Foundation
import Testing
import PDFKit
import CoreText
@testable import Molten

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("m3-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func sampleDocument(hash: String = String(repeating: "ab", count: 32)) -> MKTDocument {
    MKTDocument(
        schema: 1,
        sourceHash: hash,
        mime: "text/plain",
        extractorVersion: 1,
        ocrUsed: false,
        chunkerVersion: 1,
        pages: [MKTPage(index: 1, charStart: 0, charEnd: 100)],
        chunks: [
            MKTChunk(i: 0, text: "First chunk about tax law.", page: 1, charStart: 0, charEnd: 26, tokens: 7),
            MKTChunk(i: 1, text: "Second chunk about marine biology.", page: 1, charStart: 26, charEnd: 60, tokens: 6),
        ],
        encryption: nil,
        createdBy: "test-device",
        createdAt: "2026-11-13T00:00:00Z")
}

@Suite("M3 — MKT/MKV codecs (§7.3 round-trips)")
struct CodecTests {
    @Test func mktRoundTrip() throws {
        let document = sampleDocument()
        let encoded = try MKTCodec.encode(document)
        #expect(encoded.prefix(4) == Data("MKT1".utf8))
        let decoded = try MKTCodec.decode(encoded)
        #expect(decoded == document)
    }

    @Test func mkvRoundTrip() throws {
        let vectors: [[Float]] = (0..<5).map { i in (0..<384).map { j in Float(i) * 0.001 + Float(j) * 0.0001 } }
        let header = MKVHeader(
            schema: 1, sourceHash: "hash", profileID: "e5s-v1",
            modelRevision: "rev", dims: 384, count: 5, chunkerVersion: 1,
            encryption: nil, createdBy: "test", createdAt: "2026-11-13T00:00:00Z")
        let encoded = try MKVCodec.encode(header: header, vectors: vectors)
        #expect(encoded.prefix(4) == Data("MKV1".utf8))
        let (decodedHeader, decodedVectors) = try MKVCodec.decode(encoded)
        #expect(decodedHeader == header)
        #expect(decodedVectors.count == 5)
        for (a, b) in zip(vectors, decodedVectors) {
            for (x, y) in zip(a, b) {
                #expect(abs(x - y) < 0.001) // fp16 storage tolerance
            }
        }
    }

    @Test func mkvShapeMismatchThrows() {
        let header = MKVHeader(
            schema: 1, sourceHash: "h", profileID: "p", modelRevision: "r",
            dims: 4, count: 2, chunkerVersion: 1, encryption: nil,
            createdBy: "t", createdAt: "t")
        #expect(throws: (any Error).self) {
            try MKVCodec.encode(header: header, vectors: [[1, 2, 3]])
        }
    }

    @Test func badMagicThrows() {
        #expect(throws: (any Error).self) { try MKTCodec.decode(Data("NOPE".utf8)) }
        #expect(throws: (any Error).self) { try MKVCodec.decode(Data("NOPE1234".utf8)) }
    }

    @Test func lzfseRoundTrip() throws {
        let payload = Data(String(repeating: "knowledge base content ", count: 5000).utf8)
        let compressed = try #require(compressLZFSE(payload))
        #expect(compressed.count < payload.count)
        #expect(decompressLZFSE(compressed) == payload)
    }
}

@Suite("M3 — Chunker boundaries (K-P9)")
struct ChunkerTests {
    private func counter(_ text: String) async -> Int { max(1, text.count / 4) }

    @Test func emptyTextProducesNoChunks() async {
        let chunks = await Chunker.chunk(text: "   \n\n  ", pages: [], prefix: "passage: ", tokenCount: counter)
        #expect(chunks.isEmpty)
    }

    @Test func shortTextSingleChunk() async {
        let chunks = await Chunker.chunk(text: "A short paragraph.", pages: [MKTPage(index: 1, charStart: 0, charEnd: 18)], prefix: "passage: ", tokenCount: counter)
        #expect(chunks.count == 1)
        #expect(chunks[0].page == 1)
        #expect(chunks[0].charStart == 0)
    }

    @Test func longTextSplitsWithinCapAndOverlaps() async {
        let paragraph = "This paragraph discusses practical implications of local knowledge bases. "
        let text = String(repeating: paragraph + "\n\n", count: 60)
        let pages = [MKTPage(index: 1, charStart: 0, charEnd: (text as NSString).length)]
        let chunks = await Chunker.chunk(text: text, pages: pages, prefix: "passage: ", tokenCount: counter)
        #expect(chunks.count > 3)
        for chunk in chunks {
            #expect(chunk.tokens <= 480)
            #expect(chunk.charEnd > chunk.charStart)
        }
        // Overlap: consecutive chunks share source range (K-P9 ~50 tokens).
        var overlaps = 0
        for i in 1..<chunks.count where chunks[i].charStart < chunks[i - 1].charEnd {
            overlaps += 1
        }
        #expect(overlaps > 0)
    }

    @Test func oversizedSingleBlockSplits() async {
        let text = String(repeating: "word ", count: 4000) // one giant paragraph
        let chunks = await Chunker.chunk(text: text, pages: [], prefix: "passage: ", tokenCount: counter)
        #expect(chunks.count > 1)
        for chunk in chunks { #expect(chunk.tokens <= 480) }
    }

    @Test func chunkIndicesSequential() async {
        let text = String(repeating: "Paragraph about testing.\n\n", count: 40)
        let chunks = await Chunker.chunk(text: text, pages: [], prefix: "passage: ", tokenCount: counter)
        for (i, chunk) in chunks.enumerated() { #expect(chunk.i == i) }
    }
}

@Suite("M3 — KnowledgeStore + retrieval (K-D4/K-R2/K-R6)", .serialized)
struct StoreTests {
    @Test func ingestAndKeywordSearch() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KnowledgeStore(directory: dir)
        let mkt = dir.appendingPathComponent("doc.mkt")
        try MKTCodec.encode(sampleDocument()).write(to: mkt)
        try await store.ingest(mkt: mkt, base: "Tax", name: "tax.txt")

        let hits = await store.search("marine biology", queryVector: nil, base: "Tax", limit: 5)
        #expect(hits.contains { $0.text.contains("marine biology") })
        #expect(await store.documentCount(base: "Tax") == 1)

        // Base isolation.
        let other = await store.search("marine biology", queryVector: nil, base: "Other", limit: 5)
        #expect(other.isEmpty)
    }

    @Test func removeDocumentClearsChunks() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KnowledgeStore(directory: dir)
        let mkt = dir.appendingPathComponent("doc.mkt")
        let document = sampleDocument()
        try MKTCodec.encode(document).write(to: mkt)
        try await store.ingest(mkt: mkt, base: "B", name: "d.txt")
        await store.removeDocument(hash: document.sourceHash)
        #expect(await store.documentCount(base: "B") == 0)
        #expect(await store.search("tax", queryVector: nil, base: "B", limit: 5).isEmpty)
    }

    @Test func retrieverFallsBackToKeywordWithoutModel() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KnowledgeStore(directory: dir)
        let mkt = dir.appendingPathComponent("doc.mkt")
        try MKTCodec.encode(sampleDocument()).write(to: mkt)
        try await store.ingest(mkt: mkt, base: "B", name: "d.txt")
        // Fresh EmbeddingService: model not loaded → keyword-only (A11).
        let retriever = Retriever(store: store, embeddings: EmbeddingService())
        let result = await retriever.retrieve(query: "tax law", base: "B")
        #expect(result.mode == .keywordOnly)
        #expect(!result.passages.isEmpty)
    }

    @Test func hybridRankingWithVectors() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = KnowledgeStore(directory: dir)
        let document = sampleDocument()
        let mkt = dir.appendingPathComponent("doc.mkt")
        try MKTCodec.encode(document).write(to: mkt)
        try await store.ingest(mkt: mkt, base: "B", name: "d.txt")
        // Two unit vectors; chunk 1 aligns with the query.
        var v0 = [Float](repeating: 0, count: 384); v0[0] = 1
        var v1 = [Float](repeating: 0, count: 384); v1[1] = 1
        let header = MKVHeader(
            schema: 1, sourceHash: document.sourceHash,
            profileID: EmbeddingProfile.e5sV1.id,
            modelRevision: EmbeddingProfile.e5sV1.modelRevision,
            dims: 384, count: 2, chunkerVersion: 1, encryption: nil,
            createdBy: "t", createdAt: "t")
        let mkv = dir.appendingPathComponent("doc.mkv")
        try MKVCodec.encode(header: header, vectors: [v0, v1]).write(to: mkv)
        try await store.ingest(mkv: mkv)
        var query = [Float](repeating: 0, count: 384); query[1] = 1
        let hits = await store.search("unrelated terms", queryVector: query, base: "B", limit: 2)
        #expect(hits.first?.text.contains("marine biology") == true)
    }
}

@Suite("M3 — Extraction fixtures (K-P8)")
struct ExtractionTests {
    @Test func plainTextAndMarkdown() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("note.md")
        try "# Heading\n\nBody text about contracts.".write(to: file, atomically: true, encoding: .utf8)
        let extractor = try #require(ExtractorFactory.extractor(for: file, ocrAllowed: false))
        let result = try await extractor.extract(from: file)
        #expect(result.text.contains("contracts"))
        #expect(result.pages.count == 1)
        #expect(!result.ocrUsed)
    }

    @Test func unsupportedExtensionReturnsNil() {
        let url = URL(fileURLWithPath: "/tmp/file.xyz")
        #expect(ExtractorFactory.extractor(for: url, ocrAllowed: false) == nil)
    }

    @Test func imageOCRRequiresPlus() {
        let url = URL(fileURLWithPath: "/tmp/scan.png")
        #expect(ExtractorFactory.extractor(for: url, ocrAllowed: false) == nil)
        #expect(ExtractorFactory.extractor(for: url, ocrAllowed: true) != nil)
    }

    @Test func generatedPDFExtractsWithPages() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("fixture.pdf")
        // Generate a real text PDF via Core Graphics (extractable by PDFKit).
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData) else { return }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
        for i in 0..<3 {
            ctx.beginPDFPage(nil)
            let text = "Page \(i + 1) content about research topic \(i)."
            let attributed = NSAttributedString(string: text, attributes: [.font: PlatformFont.systemFont(ofSize: 14)])
            let line = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: 40, y: 700)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        try pdfData.write(to: file)

        let extractor = try #require(ExtractorFactory.extractor(for: file, ocrAllowed: false))
        let result = try await extractor.extract(from: file)
        #expect(result.text.contains("research topic 1"))
        #expect(result.pages.count == 3)
    }
}

@Suite("M3 — Prompt assembly + budget (K-R4/X2)")
struct AssemblyTests {
    private func passage(_ i: Int) -> Passage {
        Passage(id: "p\(i)", text: String(repeating: "content ", count: 50),
                sourceName: "file\(i).pdf", page: i, charStart: 0, charEnd: 100, score: 1)
    }

    @Test func appleModelGetsAtMostThreeChunks() {
        let assembled = PromptAssembler.assemble(
            passages: (0..<8).map(passage), budgetTokens: 100_000,
            isAppleModel: true, tokenCount: { $0.count / 4 })
        #expect(assembled.chunks.count == 3)
        #expect(assembled.contextText.contains("[1]"))
        #expect(assembled.contextText.contains("[3]"))
        #expect(!assembled.contextText.contains("[4]"))
    }

    @Test func budgetLimitsChunks() {
        let assembled = PromptAssembler.assemble(
            passages: (0..<8).map(passage), budgetTokens: 200,
            isAppleModel: false, tokenCount: { $0.count / 4 })
        #expect(assembled.chunks.count < 8)
        #expect(assembled.chunks.count >= 1)
    }

    @Test func citationInstructionPresent() {
        let assembled = PromptAssembler.assemble(
            passages: [passage(0)], budgetTokens: 10_000,
            isAppleModel: false, tokenCount: { $0.count / 4 })
        #expect(assembled.instruction.contains("Cite"))
    }

    @Test func budgetReserveAndAllocation() {
        #expect(ContextBudget.defaultReserve(window: 8192) == 1024)
        #expect(ContextBudget.defaultReserve(window: 2048) == 512)
        let budget = ContextBudget()
        let allocation = budget.allocate(
            window: 4096, system: 100, reserve: 1024,
            chunks: (0..<20).map(passage), history: [])
        #expect(allocation.usedTokens <= 4096 - 1024)
        #expect(!allocation.chunks.isEmpty)
    }
}

@Suite("M3 — End-to-end local pipeline (no model)", .serialized)
struct EndToEndPipelineTests {
    @Test func fileToCitedContext() async throws {
        // Full local path: extract → chunk → MKT → ingest → search →
        // numbered citation context. No embedding model required (A11).
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("contracts.md")
        try "# Contracts\n\nThe termination clause requires 30 days notice.\n\nPayment terms are net 60 for enterprise clients.".write(to: source, atomically: true, encoding: .utf8)

        let extractor = try #require(ExtractorFactory.extractor(for: source, ocrAllowed: false))
        let extracted = try await extractor.extract(from: source)
        let chunks = await Chunker.chunk(text: extracted.text, pages: extracted.pages,
                                         prefix: "passage: ", tokenCount: { max(1, $0.count / 4) })
        #expect(!chunks.isEmpty)
        let hash = try KnowledgeIndexer.sha256(of: source)
        let document = MKTDocument(schema: 1, sourceHash: hash, mime: "text/markdown",
                                   extractorVersion: 1, ocrUsed: false, chunkerVersion: 1,
                                   pages: extracted.pages, chunks: chunks, encryption: nil,
                                   createdBy: "test", createdAt: "t")
        let mkt = dir.appendingPathComponent("\(hash).mkt")
        try MKTCodec.encode(document).write(to: mkt)

        let store = KnowledgeStore(directory: dir)
        try await store.ingest(mkt: mkt, base: "Legal", name: source.lastPathComponent)
        let hits = await store.search("termination notice", queryVector: nil, base: "Legal", limit: 8)
        #expect(!hits.isEmpty)

        let assembled = PromptAssembler.assemble(passages: hits, budgetTokens: 4000,
                                                 isAppleModel: false, tokenCount: { $0.count / 4 })
        #expect(assembled.contextText.contains("[1]"))
        #expect(assembled.contextText.contains("contracts.md"))
        #expect(assembled.instruction.contains("Cite"))
    }

    @Test func baseStatusVocabulary() {
        #expect(BaseStatus.label(documents: 3, files: 3, chunks: 30, vectors: 30, waitingForMac: false, processing: false, error: nil) == "Indexed")
        #expect(BaseStatus.label(documents: 3, files: 3, chunks: 30, vectors: 0, waitingForMac: false, processing: false, error: nil) == "Text ready — semantic search pending")
        #expect(BaseStatus.label(documents: 1, files: 3, chunks: 10, vectors: 10, waitingForMac: false, processing: false, error: nil) == "Needs re-index")
        #expect(BaseStatus.label(documents: 1, files: 3, chunks: 10, vectors: 0, waitingForMac: true, processing: false, error: nil) == "Waiting for Mac")
        #expect(BaseStatus.label(documents: 1, files: 3, chunks: 10, vectors: 0, waitingForMac: false, processing: true, error: nil) == "Processing 1/3")
        #expect(BaseStatus.label(documents: 0, files: 0, chunks: 0, vectors: 0, waitingForMac: false, processing: false, error: "boom").hasPrefix("Error"))
    }
}

#if os(macOS)
private typealias PlatformFont = NSFont
#else
private typealias PlatformFont = UIFont
#endif

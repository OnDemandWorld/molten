//
//  ReviewFixesTests.swift
//  MoltenTests
//
//  Regression coverage for the 2026-11-24 full-project review fixes:
//  think-tag ordering trap, stale-generation completion guard, deflate
//  decompression cap, and watcher prune name-collision handling.
//

import Testing
import Foundation
import Compression
@testable import Molten

// MARK: - MessageSD think-tag ordering (crash fix)

@Suite("Review fixes — think-tag ordering")
struct ThinkTagOrderTests {
    @Test func closingTagBeforeOpeningTagDoesNotTrap() {
        // "</think>" before "": the old Range slice trapped on the
        // precondition. Malformed input must render as plain content.
        let message = MessageSD(content: "</think> oops  later", role: "user")
        #expect(message.hasThink == false)
        #expect(message.realContent == message.content)
    }

    @Test func wellFormedThinkBlockStillParses() {
        let message = MessageSD(content: "pre<think>reasoning</think>answer", role: "assistant")
        #expect(message.hasThink == true)
        #expect(message.think == "reasoning")
        #expect(message.thinkComplete == true)
        #expect(message.realContent == "answer")
    }

    @Test func unclosedThinkBlockIsIncomplete() {
        let message = MessageSD(content: "x<think>partial", role: "assistant")
        #expect(message.hasThink == true)
        #expect(message.thinkComplete == false)
        #expect(message.think == "partial")
    }
}

// MARK: - ConversationStore stale-generation guard (Stop/resend race fix)

@MainActor
@Suite("Review fixes — stale generation completion")
struct StaleGenerationTests {
    private func makeStore() -> ConversationStore {
        ConversationStore(swiftDataService: SwiftDataService(inMemory: true))
    }

    @Test func staleEpochCompletionIsANoOp() {
        let store = makeStore()
        let message = MessageSD(content: "partial", role: "assistant")
        store.messages = [message]

        store.handleComplete(requestStart: Date(), epoch: -1)

        #expect(message.done == false)
        #expect(store.conversationState == .completed)
    }

    @Test func currentEpochCompletionFinalizes() {
        let store = makeStore()
        let message = MessageSD(content: "answer", role: "assistant")
        store.messages = [message]

        store.handleComplete(requestStart: Date(), epoch: 0)

        #expect(message.done == true)
    }

    @Test func completionAfterStopDoesNotRefinalize() {
        let store = makeStore()
        let message = MessageSD(content: "partial", role: "assistant")
        store.messages = [message]

        store.stopGenerate()          // finalizes and bumps the epoch
        message.done = false          // a new generation reuses the slot

        // The stopped generation's late completion carries the old epoch.
        store.handleComplete(requestStart: Date(), epoch: 0)

        #expect(message.done == false)
    }
}

// MARK: - inflateRawDeflate cap (deflate-bomb fix)

@Suite("Review fixes — deflate decompression cap")
struct InflateCapTests {
    private func deflate(_ data: Data) -> Data? {
        let capacity = data.count + 4096
        var output = Data(count: capacity)
        let written = data.withUnsafeBytes { src in
            output.withUnsafeMutableBytes { dst in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        return written == 0 ? nil : output.prefix(written)
    }

    @Test func normalRoundTripStillWorks() throws {
        let original = Data(String(repeating: "hello molten ", count: 500).utf8)
        let compressed = try #require(deflate(original))
        let decoded = try #require(inflateRawDeflate(compressed))
        #expect(decoded == original)
    }

    @Test func deflateBombIsRefusedAtTheCap() throws {
        // 65 MiB of zeros compresses to a few tens of KB. Decoding must
        // refuse at the 64 MiB cap instead of growing the buffer unbounded.
        let bomb = Data(count: 65 * 1024 * 1024)
        let compressed = try #require(deflate(bomb))
        #expect(compressed.count < 1024 * 1024)
        #expect(inflateRawDeflate(compressed) == nil)
    }
}

// MARK: - Model catalog survives provider failures

@Suite("Review fixes — model catalog durability")
struct ModelCatalogTests {
    @Test func failedProviderKeepsStoredModels() async throws {
        let service = SwiftDataService(inMemory: true)
        let swama = LanguageModelSD(name: "s-model", modelProvider: .swama)
        let ollama = LanguageModelSD(name: "o-model", modelProvider: .ollama)
        try await service.saveModels(models: [swama, ollama], respondedProviders: [.swama, .ollama])

        // Swama answered with an empty list; Ollama is down (no response).
        try await service.saveModels(models: [], respondedProviders: [.swama])

        let stored = try await service.fetchModels()
        #expect(stored.contains { $0.name == "o-model" })   // kept: provider down
        #expect(!stored.contains { $0.name == "s-model" })  // gone: provider answered
    }
}

// MARK: - Day delete cascades + FTS removal + image round-trip

@Suite("Review fixes — persistence integrity")
struct PersistenceIntegrityTests {
    @Test func deletingDayRemovesItsMessages() async throws {
        let service = SwiftDataService(inMemory: true)
        let conversation = ConversationSD(name: "c")
        try await service.createConversation(conversation)
        let id = conversation.id
        let message = MessageSD(content: "hello", role: "user")
        message.conversation = conversation
        try await service.createMessage(message)

        try await service.deleteConversations(Date(), calendar: .current)

        // Batch delete used to bypass .cascade and orphan these rows.
        let remaining = try await service.fetchMessages(id)
        #expect(remaining.isEmpty)
    }

    @Test func removeMessageDropsSearchHit() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("molten-fts-\(UUID().uuidString)", isDirectory: true)
        let search = ConversationSearch(directory: dir)
        let conversation = ConversationSD(name: "conv")
        let message = MessageSD(content: "zebra quotation", role: "user")
        search.indexMessage(message, conversation: conversation)
        #expect(search.search("zebra").count == 1)

        search.removeMessage(messageID: message.id)
        #expect(search.search("zebra").isEmpty)
    }

    @Test func exportImportRoundTripsImages() async throws {
        let service = SwiftDataService(inMemory: true)
        let conversation = ConversationSD(name: "img")
        try await service.createConversation(conversation)
        let originalID = conversation.id
        let message = MessageSD(content: "look", role: "user", image: Data([1, 2, 3]))
        message.conversation = conversation
        try await service.createMessage(message)

        let exported = Exporter.exported(conversation, includeAnalytics: false)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let count = try await Importer.importJSON(try encoder.encode(exported), service: service)
        #expect(count == 1)

        let conversations = try await service.fetchConversations()
        let imported = try #require(conversations.first { $0.id != originalID && $0.name == "img" })
        let messages = try await service.fetchMessages(imported.id)
        #expect(messages.first?.image == Data([1, 2, 3]))
    }
}

// MARK: - Base-name validation (G3 traversal fix)

@Suite("Review fixes — base name validation")
struct BaseNameValidationTests {
    @Test func rejectsTraversalSeparatorsAndHiddenNames() {
        let bad = ["..", ".", "../escape", "a/b", "a\\b", ".hidden", "", "   ",
                   "a:b", String(repeating: "x", count: 65)]
        for name in bad {
            #expect(ShareImport.sanitizedBaseName(name) == nil, "accepted \(name)")
        }
    }

    @Test func acceptsAndTrimsOrdinaryNames() {
        #expect(ShareImport.sanitizedBaseName("  My Base ") == "My Base")
        #expect(ShareImport.sanitizedBaseName("Contracts 2026") == "Contracts 2026")
    }
}

// MARK: - Free-limit file counting (G1 iOS bypass fix)

@Suite("Review fixes — free limit counts files present")
struct CountFilesTests {
    @Test func countsRegularFilesRecursivelyAndSkipsHidden() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("molten-count-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: dir.appendingPathComponent("a.txt"))
        try Data("b".utf8).write(to: dir.appendingPathComponent("sub/b.txt"))
        try Data("h".utf8).write(to: dir.appendingPathComponent(".hidden"))
        defer { try? FileManager.default.removeItem(at: dir) }

        // Indexed count would be 0 here (nothing processed) — the gate must
        // still see the two real files.
        #expect(BaseDetailView.countFiles(in: dir) == 2)
    }
}

// MARK: - Watcher prune (name-collision + K-D5 preservation)

@MainActor
@Suite("Review fixes — watcher prune collisions")
struct PruneMappingTests {
    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("molten-prune-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func document(hash: String) -> MKTDocument {
        MKTDocument(
            schema: 1, sourceHash: hash, mime: "text/plain",
            extractorVersion: 1, ocrUsed: false, chunkerVersion: 1,
            pages: [MKTPage(index: 1, charStart: 0, charEnd: 10)],
            chunks: [MKTChunk(i: 0, text: "chunk text", page: 1, charStart: 0, charEnd: 10, tokens: 2)],
            encryption: nil, createdBy: "test", createdAt: "2026-11-24T00:00:00Z")
    }

    private func seed(_ url: URL, content: String, base: String, name: String,
                      store: KnowledgeStore, mapping: FileMapping) async throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        let hash = try KnowledgeIndexer.sha256(of: url)
        let mkt = tempDir().appendingPathComponent("\(hash).mkt")
        try MKTCodec.encode(document(hash: hash)).write(to: mkt)
        try await store.ingest(mkt: mkt, base: base, name: name)
        await mapping.update(path: url.path, entry: FileMapEntry(hash: hash, base: base, name: name, mtime: 0))
    }

    @Test func deletingOneOfSameNameFilesKeepsSurvivorRow() async throws {
        let store = KnowledgeStore(directory: tempDir())
        let mapping = FileMapping(directory: tempDir())
        let root = tempDir()
        let a = root.appendingPathComponent("a/notes.txt")
        let b = root.appendingPathComponent("b/notes.txt")
        try await seed(a, content: "one", base: "B", name: "notes.txt", store: store, mapping: mapping)
        try await seed(b, content: "two", base: "B", name: "notes.txt", store: store, mapping: mapping)
        #expect(await store.documentCount(base: "B") == 2)

        try FileManager.default.removeItem(at: a)
        await KnowledgeSync.pruneMapping(mapping: mapping, store: store)

        // The survivor keeps its index row; only the deleted file's hash row goes.
        #expect(await store.documentCount(base: "B") == 1)
        #expect(await mapping.entry(forPath: b.path) != nil)
    }

    @Test func lastPathRemovalStillDropsRow_KD5() async throws {
        let store = KnowledgeStore(directory: tempDir())
        let mapping = FileMapping(directory: tempDir())
        let root = tempDir()
        let file = root.appendingPathComponent("a.txt")
        try await seed(file, content: "one", base: "B", name: "a.txt", store: store, mapping: mapping)
        // Duplicate mapping key for the same content (K-D5 repro shape).
        let entry = await mapping.entry(forPath: file.path)
        await mapping.update(path: file.path + "#dup", entry: try #require(entry))
        #expect(await store.documentCount(base: "B") == 1)

        try FileManager.default.removeItem(at: file)
        await KnowledgeSync.pruneMapping(mapping: mapping, store: store)

        #expect(await store.documentCount(base: "B") == 0)
    }

    @Test func evictedICloudPlaceholderKeepsEntryAndRow() async throws {
        let store = KnowledgeStore(directory: tempDir())
        let mapping = FileMapping(directory: tempDir())
        let root = tempDir()
        let file = root.appendingPathComponent("a.txt")
        try await seed(file, content: "one", base: "B", name: "a.txt", store: store, mapping: mapping)

        // Evicted, not deleted: the .icloud placeholder remains.
        try FileManager.default.removeItem(at: file)
        try Data().write(to: root.appendingPathComponent(".a.txt.icloud"))
        await KnowledgeSync.pruneMapping(mapping: mapping, store: store)

        #expect(await mapping.entry(forPath: file.path) != nil)
        #expect(await store.documentCount(base: "B") == 1)
    }
}
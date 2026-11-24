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

// MARK: - Upsell coordinator rules ("without ads" doc)

@MainActor
@Suite("Upsell coordinator rules", .serialized)
struct UpsellCoordinatorTests {
    private func make() -> (UpsellCoordinator, UserDefaults, String) {
        let name = "upsell-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let coordinator = UpsellCoordinator(defaults: defaults)
        // Rules-engine tests exercise every trigger regardless of the
        // per-release dial; each test restores the shipping default.
        UpsellCoordinator.enabledTriggers = [.groundedAnswer, .settledIn, .subscriptionLapsed, .panelThanks]
        coordinator.currentTier = { .free }
        coordinator.isStreaming = { false }
        coordinator.isPanelActive = { false }
        return (coordinator, defaults, name)
    }

    @Test func payingTierNeverPrompts() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        c.currentTier = { .plus }
        c.noteGroundedAnswer(messageID: UUID())
        #expect(c.groundedCardMessageID == nil)
    }

    @Test func firstGroundedAnswerShowsCardOnce() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        let first = UUID()
        c.noteGroundedAnswer(messageID: first)
        #expect(c.groundedCardMessageID == first)
        c.dismissPrompt()
        c.noteGroundedAnswer(messageID: UUID())
        #expect(c.groundedCardMessageID == nil)
    }

    @Test func cooldownSuppressesPrompts() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        c.noteGroundedAnswer(messageID: UUID())   // records lastPrompt = now
        c.dismissPrompt()
        // Settled conditions met, but within the 14-day cooldown.
        d.set(Date().addingTimeInterval(-6 * 86400), forKey: "installDate")
        d.set(["a", "b", "c"], forKey: "activeDays")
        d.set(30, forKey: "messages")
        c.noteEvent(.messageSent)
        #expect(c.activeSheet == nil)
    }

    @Test func maxFourPromptsEver() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        d.set(4, forKey: "promptCount")
        c.noteGroundedAnswer(messageID: UUID())
        #expect(c.groundedCardMessageID == nil)
    }

    @Test func optOutSuppressesEverything() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        c.optOut()
        c.noteGroundedAnswer(messageID: UUID())
        #expect(c.groundedCardMessageID == nil)
        #expect(c.isOptedOut)
    }

    @Test func settledInNeedsDaysMessagesAndInstallAge() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        d.set(Date().addingTimeInterval(-6 * 86400), forKey: "installDate")
        d.set(["a", "b", "c"], forKey: "activeDays")
        d.set(29, forKey: "messages")
        c.noteEvent(.messageSent)                  // 30th message
        #expect(c.activeSheet == .settledIn)
    }

    @Test func settledInNotBeforeThresholds() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        d.set(Date(), forKey: "installDate")       // too recent
        d.set(["a", "b", "c"], forKey: "activeDays")
        d.set(100, forKey: "messages")
        c.noteEvent(.messageSent)
        #expect(c.activeSheet == nil)
    }

    @Test func lapseAcknowledgedOnce() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        d.set(true, forKey: "wasSubscriptionPlus")
        c.noteEvent(.appLaunch)
        #expect(c.activeSheet == .subscriptionLapsed)
        c.dismissPrompt()
        c.noteEvent(.appLaunch)
        #expect(c.activeSheet == nil)
    }

    @Test func hardPaywallSessionSuppressesSoftPrompts() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        c.noteHardPaywall()
        c.noteGroundedAnswer(messageID: UUID())
        #expect(c.groundedCardMessageID == nil)
    }

    @Test func streamingSuppressesPrompts() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        c.isStreaming = { true }
        c.noteGroundedAnswer(messageID: UUID())
        #expect(c.groundedCardMessageID == nil)
    }

    @Test func panelThanksAtTwentyUses() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        for _ in 0..<20 { c.noteEvent(.panelUse) }
        #expect(c.activeSheet == .panelThanks)
    }

    @Test func disabledTriggerNeverPrompts() {
        let (c, d, name) = make(); defer { d.removePersistentDomain(forName: name); UpsellCoordinator.enabledTriggers = [.groundedAnswer] }
        let saved = UpsellCoordinator.enabledTriggers
        UpsellCoordinator.enabledTriggers = []
        defer { UpsellCoordinator.enabledTriggers = saved }
        c.noteGroundedAnswer(messageID: UUID())
        #expect(c.groundedCardMessageID == nil)
    }
}

// MARK: - Endpoint URL resolution (scheme heuristic fix)

@Suite("Review fixes — endpoint URL resolution")
struct EndpointResolutionTests {
    private func resolve(_ url: String) -> ProviderEndpoint {
        ProviderEndpointResolver.resolve(
            url: url, token: nil,
            urlKey: "reviewTestUri-\(UUID().uuidString)",
            tokenKey: "reviewTestToken-\(UUID().uuidString)",
            defaultLocalhost: URL(string: "http://localhost:11434")!)
    }

    @Test func uppercaseSchemeIsPreserved() {
        let endpoint = resolve("HTTP://example.com:11434")
        #expect(endpoint.baseURL.host == "example.com")
        #expect(!endpoint.disabled)
    }

    @Test func hostContainingHttpGetsAScheme() {
        let endpoint = resolve("myhttpserver.local:11434")
        #expect(endpoint.baseURL.scheme == "http")
        #expect(endpoint.baseURL.host == "myhttpserver.local")
    }

    @Test func bareLocalhostGetsAScheme() {
        let endpoint = resolve("localhost:11434")
        #expect(endpoint.baseURL.scheme == "http")
        #expect(endpoint.baseURL.host == "localhost")
    }

    @Test func storedEmptyDisables() {
        // Present-but-empty stored key = user explicitly cleared the field.
        let name = "review-endpoint-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.set("", forKey: "uri")
        defer { suite.removePersistentDomain(forName: name) }
        let endpoint = ProviderEndpointResolver.resolve(
            url: nil, token: nil, urlKey: "uri", tokenKey: "tok",
            defaultLocalhost: URL(string: "http://localhost:11434")!, defaults: suite)
        #expect(endpoint.disabled)
    }

    @Test func explicitEmptyWithoutStoredKeyDoesNotDisable() {
        // First launch / default @AppStorage value must not disable polling.
        #expect(!resolve("").disabled)
    }
}

// MARK: - Knowledge integrity (MKV validation, claim ownership, chunk caps)

@Suite("Review fixes — Knowledge integrity")
struct KnowledgeIntegrityTests {
    private func mkvData(dims: Int, count: Int) throws -> Data {
        let header = MKVHeader(
            schema: 1, sourceHash: String(repeating: "ab", count: 32),
            profileID: "e5-small-v2", modelRevision: "r", dims: dims, count: count,
            chunkerVersion: 1, encryption: nil, createdBy: "t", createdAt: "2026-11-24T00:00:00Z")
        var data = Data("MKV1".utf8)
        let json = try JSONEncoder().encode(header)
        var length = UInt32(json.count).littleEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(json)
        return data
    }

    @Test func mkvRejectsZeroDimsAndNegativeCount() throws {
        #expect(throws: (any Error).self) { try MKVCodec.decode(mkvData(dims: 0, count: 0)) }
        #expect(throws: (any Error).self) { try MKVCodec.decode(mkvData(dims: 384, count: -1)) }
    }

    @Test func staleDeviceCannotReleaseSuccessorClaim() async throws {
        final class Clock: @unchecked Sendable { var now = Date() }
        let clock = Clock()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("molten-claims-\(UUID().uuidString)", isDirectory: true)
        let a = ClaimStore(directory: dir, deviceID: "A", now: { clock.now })
        let b = ClaimStore(directory: dir, deviceID: "B", now: { clock.now })

        #expect(await a.tryClaim(hash: "h", stage: .extract))
        clock.now = Date().addingTimeInterval(700) // A's 10-minute lease expired
        #expect(await b.tryClaim(hash: "h", stage: .extract)) // takeover

        // A finishes late and releases: must NOT delete B's live claim.
        await a.release(hash: "h", stage: .extract, failed: nil)
        #expect(await a.tryClaim(hash: "h", stage: .extract) == false)
    }

    @Test func chunkerSplitsUnbrokenLongRunUnderTheCap() async {
        let run = String(repeating: "x", count: 4000) // ~1000 tokens, one "word"
        let chunks = await Chunker.chunk(
            text: run, pages: [], prefix: "passage: ",
            tokenCount: { max(1, $0.count / 4) })
        #expect(!chunks.isEmpty)
        for chunk in chunks {
            #expect(chunk.tokens <= Chunker.maxTokens)
        }
    }

    @Test func tokenEstimatorCountsCJKPerCharacter() {
        #expect(TokenEstimator.estimate("你好世界") == 4)
        #expect(TokenEstimator.estimate("hello world") == 2)
    }

    @Test func miniZipReadsStreamedZipWithDataDescriptors() throws {
        // Entry A: deflate with a data descriptor (compSize 0 in the local
        // header — Java ZipOutputStream style). Entry B: stored target.
        // Skipping A used to advance by 0 bytes and abort the scan.
        let payload = Data(String(repeating: "hello ", count: 100).utf8)
        let capacity = payload.count + 4096
        var deflated = Data(count: capacity)
        let n = payload.withUnsafeBytes { src in
            deflated.withUnsafeMutableBytes { dst in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        deflated = deflated.prefix(n)
        let target = Data("<document>text</document>".utf8)

        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func localHeader(name: String, method: UInt16, flags: UInt16, compSize: UInt32, uncompSize: UInt32) -> Data {
            var d = le32(0x04034b50)
            d += le16(20) + le16(flags) + le16(method)
            d += le16(0) + le16(0)               // time, date
            d += le32(0)                        // crc (unchecked by MiniZip)
            d += le32(compSize) + le32(uncompSize)
            d += le16(UInt16(name.utf8.count)) + le16(0)
            d += Data(name.utf8)
            return d
        }

        var zip = localHeader(name: "other.txt", method: 8, flags: 0x0008, compSize: 0, uncompSize: 0)
        zip += deflated
        zip += le32(0x08074b50) + le32(0) + le32(UInt32(deflated.count)) + le32(UInt32(payload.count))
        zip += localHeader(name: "word/document.xml", method: 0, flags: 0,
                           compSize: UInt32(target.count), uncompSize: UInt32(target.count))
        zip += target

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("molten-zip-\(UUID().uuidString).docx")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let found = try MiniZip.fileData(named: "word/document.xml", in: url)
        #expect(found == target)
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
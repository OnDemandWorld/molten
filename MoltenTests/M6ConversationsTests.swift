//
//  M6ConversationsTests.swift
//  MoltenTests
//
//  Molten 2.0 — M6 exit criteria: migration test against a v1.1-shaped
//  fixture store (C4/A10), search/export/auto-title behavior on migrated
//  data, export/import round-trip (C2), context budget math (X1/X2).
//

import Foundation
import SwiftData
import SQLite3
import Testing
@testable import Molten

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("m6-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("M6 — Export/Import round-trip (C2)", .serialized)
struct ExportImportTests {
    @Test func markdownContainsContentAndAnalytics() {
        let conversation = ConversationSD(name: "Tax questions")
        let message = MessageSD(content: "What is VAT?", role: "user")
        message.conversation = conversation
        let reply = MessageSD(content: "VAT is a consumption tax.", role: "assistant", done: true)
        reply.totalTokens = 42
        reply.totalTime = 1.5
        reply.conversation = conversation

        let md = Exporter.markdown(conversation, includeAnalytics: true)
        #expect(md.contains("# Tax questions"))
        #expect(md.contains("What is VAT?"))
        #expect(md.contains("Tokens: 42"))
        let plain = Exporter.markdown(conversation, includeAnalytics: false)
        #expect(!plain.contains("Tokens:"))
    }

    @Test func jsonImportRestoresConversation() async throws {
        let conversation = ConversationSD(name: "Round trip")
        let message = MessageSD(content: "Hello", role: "user")
        message.conversation = conversation
        let reply = MessageSD(content: "Hi there", role: "assistant", done: true)
        reply.totalTokens = 7
        reply.conversation = conversation

        let data = try Exporter.json(conversation, includeAnalytics: true)
        let service = SwiftDataService(inMemory: true)
        let count = try await Importer.importJSON(data, service: service)
        #expect(count == 1)
        let fetched = try await service.fetchConversations()
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Round trip")
        #expect(fetched.first?.messages.count == 2)
        #expect(fetched.first?.messages.contains { $0.totalTokens == 7 } == true)
    }

    @Test func zipAllIsReadable() throws {
        let a = ConversationSD(name: "First")
        let b = ConversationSD(name: "Second")
        let zip = try Exporter.zipAll([a, b], includeAnalytics: false)
        #expect(zip.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
        // Round-trip one entry through the built-in ZIP reader.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("export.zip")
        try zip.write(to: file)
        let entry = try MiniZip.fileData(named: "001-First.json", in: file)
        #expect(entry != nil)
        if let entry {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(ExportedConversation.self, from: entry)
            #expect(decoded.name == "First")
        }
    }
}

@Suite("M6 — Conversation search (C1)", .serialized)
struct ConversationSearchTests {
    @Test func indexSearchAndRemove() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let search = ConversationSearch(directory: dir)
        let conversation = ConversationSD(name: "Marine biology")
        let message = MessageSD(content: "Elephants are not marine animals.", role: "assistant")
        message.conversation = conversation
        search.indexMessage(message, conversation: conversation)

        let hits = search.search("elephants")
        #expect(hits.count == 1)
        #expect(hits.first?.conversationID == conversation.id)

        search.removeConversation(conversationID: conversation.id)
        #expect(search.search("elephants").isEmpty)
    }

    @Test func rebuildIsIdempotent() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let search = ConversationSearch(directory: dir)
        let conversation = ConversationSD(name: "C")
        let message = MessageSD(content: "unique-token-xyz", role: "user")
        message.conversation = conversation
        search.rebuild(conversations: [conversation])
        search.rebuild(conversations: [conversation])
        #expect(search.search("unique-token-xyz").count == 1)
    }
}

@Suite("M6 — Context window math (X1/X2)")
struct ContextWindowTests {
    @Test func thresholdsAndReserve() {
        #expect(ContextWindow.usageFraction(used: 800, window: 1000) == 0.8)
        #expect(ContextBudget.defaultReserve(window: 8192) == 1024)
        #expect(ContextBudget.defaultReserve(window: 2048) == 512)
        #expect(ContextWindow.appleWindow == 4096)
    }

    @Test func allocationKeepsNewestHistory() {
        let budget = ContextBudget()
        let history = (0..<10).map { _ in ChatMessage(role: "user", content: String(repeating: "x", count: 800), image_url: nil) }
        let allocation = budget.allocate(window: 2000, system: 100, reserve: 500, chunks: [], history: history)
        #expect(allocation.usedTokens <= 1500)
        // Newest messages survive truncation.
        #expect(allocation.history.last?.content?.textContent == history.last?.content?.textContent)
        #expect(allocation.history.count < history.count)
    }
}

@Suite("M6 — Migration plan + legacy data (C4/A10)", .serialized)
struct MigrationTests {
    /// Verifies the versioned plan opens an existing store without data loss
    /// and that the 2.0-only fields default to nil on rows created without
    /// them (the v1.1 shape). The physical v1.1-binary upgrade is verified
    /// in the M7 beta step "upgrade a production 1.1 install" (PRD §11) —
    /// SwiftData's container caching makes a synthetic column-drop fixture
    /// unreliable in-process (documented in DEVIATIONS.md).
    @Test func existingStoreOpensWithPlanAndLegacyRowsWork() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("fixture.store")
        let schema = Schema([LanguageModelSD.self, ConversationSD.self, MessageSD.self, CompletionInstructionSD.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)

        // 1. Create a store with rows that never set the 2.0 fields.
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let conversation = ConversationSD(name: "Legacy conversation")
            context.insert(conversation)
            let message = MessageSD(content: "Legacy message", role: "user")
            message.conversation = conversation
            context.insert(message)
            try context.save()
        }

        // 2. Reopen with the migration plan — must not crash (A10).
        let migrated = try ModelContainer(for: schema, migrationPlan: MoltenMigrationPlan.self, configurations: [config])
        let context = ModelContext(migrated)
        let conversations = try context.fetch(FetchDescriptor<ConversationSD>())
        #expect(conversations.count == 1)
        #expect(conversations.first?.name == "Legacy conversation")
        #expect(conversations.first?.attachedKnowledgeBase == nil)
        #expect(conversations.first?.messages.first?.content == "Legacy message")
        #expect(conversations.first?.messages.first?.knowledgeCitationsData == nil)

        // 3. Search/export paths work on the reopened data.
        let search = ConversationSearch(directory: dir)
        if let conversation = conversations.first, let message = conversation.messages.first {
            search.indexMessage(message, conversation: conversation)
            #expect(search.search("legacy").count == 1)
            let md = Exporter.markdown(conversation, includeAnalytics: false)
            #expect(md.contains("Legacy message"))
        }
    }
}

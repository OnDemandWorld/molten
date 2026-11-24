//
//  SwiftDataService.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData

final actor SwiftDataService: ModelActor {
    let modelContainer: ModelContainer
    let modelExecutor: ModelExecutor
    private let modelContext: ModelContext
    
    static let shared = SwiftDataService()

    /// - Parameter inMemory: when true, the container is backed by an in-memory
    ///   store. Used by tests to avoid touching the user's on-disk data.
    ///   Production behavior (`SwiftDataService.shared`) is unchanged.
    init(inMemory: Bool = false) {
        let sharedModelContainer: ModelContainer = {
            let schema = Schema([
                LanguageModelSD.self,
                ConversationSD.self,
                MessageSD.self,
                CompletionInstructionSD.self
            ])
            // K-D4: no database is synced. CloudKit must be explicitly .none —
            // with iCloud entitlements present, .automatic enables CloudKit
            // integration, which rejects non-optional attributes without
            // defaults (crash on device). Chat-history sync is a 2.1 feature.
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: .none)

            do {
                // C4: versioned migration plan (v1.1 → 2.0 is additive
                // optional fields, handled lightweight by SwiftData).
                return try ModelContainer(
                    for: schema,
                    migrationPlan: MoltenMigrationPlan.self,
                    configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }()

        self.modelContext = ModelContext(sharedModelContainer)
        self.modelContext.autosaveEnabled = false
        modelContainer = sharedModelContainer
        modelExecutor = DefaultSerialModelExecutor(modelContext: modelContext)
    }
}

// MARK: - Language Models
extension SwiftDataService {
    func fetchModels() throws -> [LanguageModelSD] {
        let sortDescriptor = SortDescriptor(\LanguageModelSD.name)
        let fetchDescriptor = FetchDescriptor<LanguageModelSD>(sortBy: [sortDescriptor])
        let models = try modelContext.fetch(fetchDescriptor)
        
        return models
    }
    
    /// Upsert by unique name; delete only models from providers that
    /// actually responded. A provider that was down or threw keeps its
    /// stored rows — a transient fetch error must not wipe the catalog and
    /// nullify every conversation.model (review 2026-11-24).
    func saveModels(models: [LanguageModelSD], respondedProviders: Set<ModelProvider>) throws {
        let existing = try modelContext.fetch(FetchDescriptor<LanguageModelSD>())
        let existingByName = Dictionary(
            existing.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let incomingNames = Set(models.map(\.name))
        for model in models {
            if let stored = existingByName[model.name] {
                stored.imageSupport = model.imageSupport
                stored.modelProvider = model.modelProvider
            } else {
                modelContext.insert(model)
            }
        }
        for stored in existing where !incomingNames.contains(stored.name) {
            if let provider = stored.modelProvider, respondedProviders.contains(provider) {
                modelContext.delete(stored)
            }
        }
        try modelContext.saveChanges()
    }
    
    func deleteModels() throws {
        try modelContext.delete(model: LanguageModelSD.self)
        try modelContext.saveChanges()
    }
}

// MARK: - Conversations
extension SwiftDataService {
    func createConversation(_ conversation: ConversationSD) throws {
        self.modelContext.insert(conversation)
        try modelContext.saveChanges()
    }
    
    func renameConversation(_ conversation: ConversationSD) throws {
        try modelContext.saveChanges()
        ConversationSearch.shared.renameConversation(conversationID: conversation.id, name: conversation.name)
    }

    /// Rename by ID, fetching on the data actor — callers off the owning
    /// context (AutoTitler) must not mutate the model directly
    /// (review 2026-11-24).
    func renameConversation(id: UUID, name: String) throws {
        guard let conversation = try getConversation(id) else { return }
        conversation.name = name
        try renameConversation(conversation)
    }

    /// Everything AutoTitler needs, read on the owning context.
    struct TitleSnapshot {
        let name: String
        let firstUserContent: String
        let firstAssistantContent: String
    }

    func titleSnapshot(conversationID: UUID) throws -> TitleSnapshot? {
        guard let conversation = try getConversation(conversationID) else { return nil }
        let messages = conversation.messages.sorted { $0.createdAt < $1.createdAt }
        guard let firstUser = messages.first(where: { $0.role == "user" }),
              let firstAssistant = messages.first(where: { $0.role == "assistant" && $0.done })
        else { return nil }
        return TitleSnapshot(
            name: conversation.name,
            firstUserContent: firstUser.content,
            firstAssistantContent: firstAssistant.realContent ?? firstAssistant.content)
    }

    func deleteConversation(_ conversation: ConversationSD) throws {
        let id = conversation.id
        self.modelContext.delete(conversation)
        try modelContext.saveChanges()
        ConversationSearch.shared.removeConversation(conversationID: id)
    }
    
    func updateConversation(_ conversation: ConversationSD) throws {
        conversation.updatedAt = .now
        try modelContext.saveChanges()
    }
    
    func fetchConversations() async throws -> [ConversationSD] {
        let sortDescriptor = SortDescriptor(\ConversationSD.updatedAt, order: .reverse)
        let fetchDescriptor = FetchDescriptor<ConversationSD>(sortBy: [sortDescriptor])
        // Ensure fetch runs at appropriate QoS to avoid priority inversion
        return try await Task(priority: .userInitiated) {
            try modelContext.fetch(fetchDescriptor)
        }.value
    }
    
    func getConversation(_ conversationId: UUID) throws -> ConversationSD? {
        let predicate = #Predicate<ConversationSD>{ $0.id == conversationId }
        let fetchDescriptor = FetchDescriptor<ConversationSD>(predicate: predicate)
        let conversations = try modelContext.fetch(fetchDescriptor)
        return conversations.first
    }
    
    func deleteConversations() throws {
        try modelContext.delete(model: ConversationSD.self)
        try modelContext.saveChanges()
        ConversationSearch.shared.removeAll()
    }

    func deleteMessages() throws {
        try modelContext.delete(model: MessageSD.self)
        try modelContext.saveChanges()
        ConversationSearch.shared.removeAll()
    }
    
    /// Deletes conversations whose `updatedAt` falls within the calendar day
    /// containing `date` (half-open interval: startOfDay ..< startOfNextDay).
    /// Matches the sidebar grouping in ConversationHistoryList, which groups by
    /// `Calendar.current.startOfDay(for: updatedAt)`.
    func deleteConversations(_ date: Date, calendar: Calendar = .current) throws {
        let startOfDay = calendar.startOfDay(for: date)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        let predicate = #Predicate<ConversationSD> { $0.updatedAt >= startOfDay && $0.updatedAt < startOfNextDay }
        // C1: capture IDs before deletion so the FTS sidecar stays in sync.
        let doomed = try modelContext.fetch(FetchDescriptor<ConversationSD>(predicate: predicate))
        // Delete per-object, NOT via the batch API: batch delete bypasses
        // the .cascade rule and orphans every message of the deleted day
        // (review 2026-11-24).
        for conversation in doomed {
            modelContext.delete(conversation)
        }
        try modelContext.saveChanges()
        for conversation in doomed {
            ConversationSearch.shared.removeConversation(conversationID: conversation.id)
        }
    }
}


// MARK: - Messages
extension SwiftDataService {
    func fetchMessages(_ conversationId: UUID) throws -> [MessageSD] {
        let predicate = #Predicate<MessageSD>{ $0.conversation?.id == conversationId }
        let sortDescriptor = SortDescriptor(\MessageSD.createdAt)
        let fetchDescriptor = FetchDescriptor<MessageSD>(predicate: predicate, sortBy: [sortDescriptor])
        return try modelContext.fetch(fetchDescriptor)
    }
    
    func updateMessage(_ message: MessageSD) throws {
        try modelContext.saveChanges()
        if let conversation = message.conversation {
            ConversationSearch.shared.indexMessage(message, conversation: conversation)
        }
    }

    func createMessage(_ message: MessageSD) throws {
        self.modelContext.insert(message)
        try modelContext.saveChanges()
        if let conversation = message.conversation {
            ConversationSearch.shared.indexMessage(message, conversation: conversation)
        }
    }

    /// Delete one message and its FTS row (review 2026-11-24: edit-trim
    /// used to orphan messages and leave ghost search hits).
    func deleteMessage(_ message: MessageSD) throws {
        let id = message.id
        modelContext.delete(message)
        try modelContext.saveChanges()
        ConversationSearch.shared.removeMessage(messageID: id)
    }
}

// MARK: - CompletionInstruction
extension SwiftDataService {
    func fetchCompletionInstructions() throws -> [CompletionInstructionSD] {
        let sortDescriptor = SortDescriptor(\CompletionInstructionSD.order, order: .forward)
        let fetchDescriptor = FetchDescriptor<CompletionInstructionSD>(sortBy: [sortDescriptor])
        return try modelContext.fetch(fetchDescriptor)
    }
    
    func updateCompletionInstructions(_ instructions: [CompletionInstructionSD]) throws {
        for index in instructions.indices {
            instructions[index].order = index
            modelContext.insert(instructions[index])
        }
        try modelContext.saveChanges()
    }
    
    func deleteCompletionInstruction(_ instruction: CompletionInstructionSD) throws {
        self.modelContext.delete(instruction)
        try modelContext.saveChanges()
    }
}

// MARK: - General
extension SwiftDataService {
    func deleteEverything() throws {
        try modelContext.delete(model: ConversationSD.self)
        try modelContext.delete(model: LanguageModelSD.self)
        try modelContext.delete(model: MessageSD.self)
        try modelContext.delete(model: CompletionInstructionSD.self)
        try modelContext.saveChanges()
        ConversationSearch.shared.removeAll()
    }
}

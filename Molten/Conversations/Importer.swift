//
//  Importer.swift
//  Molten
//
//  Molten 2.0 — M6, C2. Import conversations from JSON (single object or
//  array — the same shape Exporter produces).
//

import Foundation

enum Importer {
    enum ImportError: Error { case invalidFormat }

    /// Imports and returns the number of conversations created.
    @discardableResult
    static func importJSON(_ data: Data, service: SwiftDataService = .shared) async throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let conversations: [ExportedConversation]
        if let array = try? decoder.decode([ExportedConversation].self, from: data) {
            conversations = array
        } else if let single = try? decoder.decode(ExportedConversation.self, from: data) {
            conversations = [single]
        } else {
            throw ImportError.invalidFormat
        }
        var count = 0
        for exported in conversations {
            let conversation = ConversationSD(name: exported.name, updatedAt: exported.updatedAt)
            conversation.createdAt = exported.createdAt
            try await service.createConversation(conversation)
            for message in exported.messages {
                let sd = MessageSD(content: message.content, role: message.role)
                sd.createdAt = message.createdAt
                sd.done = true
                if let analytics = message.analytics {
                    sd.promptTokens = analytics.promptTokens
                    sd.completionTokens = analytics.completionTokens
                    sd.totalTokens = analytics.totalTokens
                    sd.totalTime = analytics.totalTime
                    sd.promptEvalTime = analytics.promptEvalTime
                    sd.evalTime = analytics.evalTime
                }
                sd.conversation = conversation
                try await service.createMessage(sd)
            }
            count += 1
        }
        return count
    }
}

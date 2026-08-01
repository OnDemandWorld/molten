//
//  AnalyticsTests.swift
//  MoltenTests
//
//  Coverage for the per-message analytics pipeline and its inputs
//  (ANALYTICS_REVIEW.md findings AN-1..AN-8 and the F-19 prerequisite).
//

import XCTest
import SwiftData
@testable import Molten

@MainActor
final class AnalyticsTests: XCTestCase {

    // MARK: - F-19: message history must contain each turn exactly once

    func testMessageHistoryContainsCurrentUserMessageExactlyOnce() async throws {
        let service = SwiftDataService(inMemory: true)
        let conversation = ConversationSD(name: "history")
        try await service.createConversation(conversation)

        let earlier = MessageSD(content: "first user turn", role: "user")
        earlier.createdAt = Date(timeIntervalSince1970: 1000)
        earlier.conversation = conversation
        try await service.createMessage(earlier)

        let current = MessageSD(content: "second user turn", role: "user")
        current.createdAt = Date(timeIntervalSince1970: 2000)
        current.conversation = conversation
        try await service.createMessage(current)

        // Empty assistant placeholder, as sendPrompt creates after building history.
        let placeholder = MessageSD(content: "", role: "assistant")
        placeholder.createdAt = Date(timeIntervalSince1970: 3000)
        placeholder.conversation = conversation
        try await service.createMessage(placeholder)

        let history = ConversationStore.messageHistory(
            from: conversation.messages.sorted { $0.createdAt < $1.createdAt }
        )

        let userTurns = history.filter { $0.role == "user" }
        XCTAssertEqual(userTurns.count, 2, "each user turn must appear exactly once (F-19)")
        XCTAssertEqual(userTurns.map { $0.content?.stringValue }, ["first user turn", "second user turn"])
        XCTAssertFalse(history.contains { $0.role == "assistant" },
                       "empty assistant placeholders must not be sent as blank turns")
    }

    func testMessageHistoryKeepsAssistantTurnsWithContent() async throws {
        let service = SwiftDataService(inMemory: true)
        let conversation = ConversationSD(name: "history")
        try await service.createConversation(conversation)

        let user = MessageSD(content: "hello", role: "user")
        user.createdAt = Date(timeIntervalSince1970: 1000)
        user.conversation = conversation
        try await service.createMessage(user)

        let assistant = MessageSD(content: "hi there", role: "assistant")
        assistant.createdAt = Date(timeIntervalSince1970: 2000)
        assistant.conversation = conversation
        try await service.createMessage(assistant)

        let history = ConversationStore.messageHistory(
            from: conversation.messages.sorted { $0.createdAt < $1.createdAt }
        )

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.map { $0.role }, ["user", "assistant"])
    }
}

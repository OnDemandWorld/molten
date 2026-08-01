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

    // MARK: - AN-1/AN-2: computeAnalytics prefers server-reported values

    func testComputeAnalyticsPrefersServerReportedValues() {
        let usage = Usage(
            prompt_tokens: 100, completion_tokens: 50, total_tokens: 150,
            prompt_eval_duration: 0.5, eval_duration: 2.0, total_duration: 2.5,
            response_tokens_per_second: 25
        )
        let start = Date(timeIntervalSince1970: 0)

        let result = ConversationStore.computeAnalytics(
            usage: usage,
            promptCharacterCount: 9999,        // estimates must be ignored
            completionCharacterCount: 9999,
            requestStart: start,
            firstTokenTime: nil,               // client stamp absent — irrelevant
            completionTime: start.addingTimeInterval(30)
        )

        XCTAssertEqual(result.promptTokens, 100)
        XCTAssertEqual(result.completionTokens, 50)
        XCTAssertEqual(result.totalTokens, 150)
        XCTAssertEqual(result.promptEvalTime ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(result.evalTime ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(result.totalTime ?? -1, 2.5, accuracy: 1e-9)
    }

    func testComputeAnalyticsTotalOnlyKeepsClientSplitUnderServerTotal() {
        // Swama reports total_duration but no prompt/eval split.
        let usage = Usage(
            prompt_tokens: 10, completion_tokens: 5, total_tokens: 15,
            prompt_eval_duration: nil, eval_duration: nil, total_duration: 2.0,
            response_tokens_per_second: nil
        )
        let start = Date(timeIntervalSince1970: 0)
        let firstToken = start.addingTimeInterval(1)

        let result = ConversationStore.computeAnalytics(
            usage: usage,
            promptCharacterCount: 1, completionCharacterCount: 1,
            requestStart: start,
            firstTokenTime: firstToken,
            completionTime: start.addingTimeInterval(30)   // client total ignored
        )

        XCTAssertEqual(result.totalTime ?? -1, 2.0, accuracy: 1e-9)
        XCTAssertEqual(result.promptEvalTime ?? -1, 1.0, accuracy: 1e-9)
        XCTAssertEqual(result.evalTime ?? -1, 1.0, accuracy: 1e-9)
    }

    func testComputeAnalyticsFallsBackToEstimatesAndClientTiming() {
        let start = Date(timeIntervalSince1970: 0)
        let firstToken = start.addingTimeInterval(1)
        let end = start.addingTimeInterval(5)

        let result = ConversationStore.computeAnalytics(
            usage: nil,
            promptCharacterCount: 400,
            completionCharacterCount: 200,
            requestStart: start,
            firstTokenTime: firstToken,
            completionTime: end
        )

        XCTAssertEqual(result.promptTokens, 100)        // 400 / 4
        XCTAssertEqual(result.completionTokens, 50)     // 200 / 4
        XCTAssertEqual(result.totalTokens, 150)
        XCTAssertEqual(result.promptEvalTime ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(result.evalTime ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(result.totalTime ?? -1, 5, accuracy: 1e-9)
    }

    func testComputeAnalyticsWithoutFirstTokenAttributesAllTimeToEval() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(3)

        let result = ConversationStore.computeAnalytics(
            usage: nil,
            promptCharacterCount: 40, completionCharacterCount: 40,
            requestStart: start,
            firstTokenTime: nil,
            completionTime: end
        )

        XCTAssertEqual(result.promptEvalTime, 0)
        XCTAssertEqual(result.evalTime ?? -1, 3, accuracy: 1e-9)
        XCTAssertEqual(result.totalTime ?? -1, 3, accuracy: 1e-9)
    }

    // MARK: - AN-4: prompt character count scope

    func testPromptCharacterCountIncludesCurrentUserTurnAndSkipsPlaceholders() async throws {
        let service = SwiftDataService(inMemory: true)
        let conversation = ConversationSD(name: "counting")
        try await service.createConversation(conversation)

        let system = MessageSD(content: "be brief", role: "system")          // 8
        system.createdAt = Date(timeIntervalSince1970: 100)
        let earlierUser = MessageSD(content: "hello world", role: "user")   // 11
        earlierUser.createdAt = Date(timeIntervalSince1970: 200)
        let earlierAssistant = MessageSD(content: "hi!", role: "assistant") // 3
        earlierAssistant.createdAt = Date(timeIntervalSince1970: 300)
        let deadAssistant = MessageSD(content: "", role: "assistant")       // skipped
        deadAssistant.createdAt = Date(timeIntervalSince1970: 350)
        let currentUser = MessageSD(content: "question?", role: "user")     // 9
        currentUser.createdAt = Date(timeIntervalSince1970: 400)
        let placeholder = MessageSD(content: "", role: "assistant")         // the message itself
        placeholder.createdAt = Date(timeIntervalSince1970: 400)            // same instant!

        for message in [system, earlierUser, earlierAssistant, deadAssistant, currentUser, placeholder] {
            message.conversation = conversation
            try await service.createMessage(message)
        }

        XCTAssertEqual(ConversationStore.promptCharacterCount(for: placeholder), 8 + 11 + 3 + 9)
    }

    // MARK: - AN-1: Ollama eval-stat mapping

    func testUsageFromOllamaConvertsNanosecondsOnDoneChunk() {
        guard let usage = OllamaService.usageFromOllama(
            done: true,
            promptEvalCount: 19,
            promptEvalDuration: 100_000_000,
            evalCount: 1,
            evalDuration: 7_000_000,
            totalDuration: 3_300_000_000
        ) else {
            return XCTFail("expected usage on done chunk")
        }

        XCTAssertEqual(usage.prompt_tokens, 19)
        XCTAssertEqual(usage.completion_tokens, 1)
        XCTAssertEqual(usage.total_tokens, 20)
        XCTAssertEqual(usage.prompt_eval_duration ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(usage.eval_duration ?? -1, 0.007, accuracy: 1e-9)
        XCTAssertEqual(usage.total_duration ?? -1, 3.3, accuracy: 1e-9)
    }

    func testUsageFromOllamaIsNilBeforeDone() {
        XCTAssertNil(OllamaService.usageFromOllama(
            done: false,
            promptEvalCount: 19, promptEvalDuration: 1, evalCount: 1, evalDuration: 1, totalDuration: 1
        ))
    }

    // MARK: - AN-2: Swama usage extensions decode

    func testUsageDecodesProviderExtensions() throws {
        let json = """
        {"prompt_tokens":19,"completion_tokens":1,"total_tokens":20,
         "total_duration":3.347,"response_token/s":143.5}
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(Usage.self, from: json)

        XCTAssertEqual(usage.prompt_tokens, 19)
        XCTAssertEqual(usage.completion_tokens, 1)
        XCTAssertEqual(usage.total_tokens, 20)
        XCTAssertEqual(usage.total_duration ?? -1, 3.347, accuracy: 1e-9)
        XCTAssertEqual(usage.response_tokens_per_second ?? -1, 143.5, accuracy: 1e-9)
        XCTAssertNil(usage.prompt_eval_duration)
        XCTAssertNil(usage.eval_duration)
    }

    func testUsageDecodesMinimalPayload() throws {
        let json = #"{"prompt_tokens":5,"completion_tokens":2,"total_tokens":7}"#.data(using: .utf8)!

        let usage = try JSONDecoder().decode(Usage.self, from: json)

        XCTAssertEqual(usage.total_tokens, 7)
        XCTAssertNil(usage.total_duration)
        XCTAssertNil(usage.response_tokens_per_second)
    }

    // MARK: - AN-3: first-token stamping

    func testFirstTokenStampsOnFirstNonEmptyContentChunk() async throws {
        let service = SwiftDataService(inMemory: true)
        let store = ConversationStore(swiftDataService: service)
        let conversation = ConversationSD(name: "timing")
        try await service.createConversation(conversation)
        let assistant = MessageSD(content: "", role: "assistant")
        assistant.conversation = conversation
        try await service.createMessage(assistant)
        store.messages = [assistant]

        func chunk(content: String) -> ChatCompletionResponse {
            ChatCompletionResponse(
                id: "x", object: "chat.completion.chunk", created: nil, model: "m",
                choices: [Choice(
                    index: 0, message: nil,
                    delta: ChatMessage(role: "assistant", content: content, image_url: nil),
                    finish_reason: nil
                )],
                usage: nil
            )
        }

        let start = Date()
        store.handleReceive(chunk(content: ""), requestStart: start)   // role-only/empty chunk
        XCTAssertNil(store.firstTokenTime, "empty chunk must not stamp first token (AN-3)")

        store.handleReceive(chunk(content: "Hello"), requestStart: start)
        XCTAssertNotNil(store.firstTokenTime)
    }
}

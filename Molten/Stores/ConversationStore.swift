//
//  ConversationStore.swift
//  Molten
//
//  Manages conversation state, message streaming, and analytics tracking.
//  This is the core store that handles all chat interactions with model providers.
//
//  Key Responsibilities:
//  - Managing conversation state (loading, completed, error)
//  - Streaming responses from model providers
//  - Throttling UI updates to prevent freezing
//  - Tracking performance analytics (tokens, timing, rates)
//  - Coordinating between providers and UI
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//  Refactored for Molten v1.0.0
//

import Foundation
import SwiftData
import Combine
import SwiftUI

@Observable
final class ConversationStore: @unchecked Sendable {
    static let shared = ConversationStore(swiftDataService: SwiftDataService.shared)

    private var swiftDataService: SwiftDataService
    private var generationTask: Task<Void, Never>?

    /// For some reason (SwiftUI bug / too frequent UI updates) updating UI for each stream message sometimes freezes the UI.
    /// Throttling UI updates seem to fix the issue.
    /// Using array buffer instead of string concatenation for O(n) instead of O(n²) performance
    private var currentMessageBuffer: [String] = []
    private let throttler = Throttler(delay: 0.15)

    /// The assistant message currently receiving streamed content. Chunks are
    /// appended to this instance rather than `messages.last` so switching
    /// conversations mid-stream cannot write content into the wrong message.
    private var streamingMessage: MessageSD?

    // Analytics tracking
    private var requestStartTime: Date?
    /// When the first non-empty content chunk arrived. Internal for unit tests (AN-3).
    var firstTokenTime: Date?
    private var hasReceivedFirstToken: Bool = false
    /// Latest server-reported usage; providers send it with the final chunk.
    private var lastUsage: Usage?

    @MainActor var conversationState: ConversationState = .completed
    @MainActor var conversations: [ConversationSD] = []
    @MainActor var selectedConversation: ConversationSD?
    @MainActor var messages: [MessageSD] = []

    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }

    /// Reset streaming state for a new request
    @MainActor
    private func resetStreamingState() {
        currentMessageBuffer = []
        requestStartTime = nil
        firstTokenTime = nil
        hasReceivedFirstToken = false
        lastUsage = nil
        streamingMessage = nil
        generationTask?.cancel()
        generationTask = nil
    }
    
    func loadConversations() async throws {
        let fetchedConversations = try await swiftDataService.fetchConversations()
        DispatchQueue.main.async {
            self.conversations = fetchedConversations
        }
    }
    
    func deleteAllConversations() {
        Task {
            DispatchQueue.main.async { [weak self] in
                self?.messages = []
                self?.selectedConversation = nil
            }
            try? await swiftDataService.deleteConversations()
            try? await swiftDataService.deleteMessages()
            try? await loadConversations()
        }
    }
    
    @MainActor
    func deleteDailyConversations(_ date: Date) async {
        // The sidebar groups conversations by Calendar.current.startOfDay(of: updatedAt),
        // so the open conversation is part of the tapped day group exactly when its
        // updatedAt falls on that calendar day.
        let deletesSelectedConversation = selectedConversation.map {
            Calendar.current.isDate($0.updatedAt, inSameDayAs: date)
        } ?? false

        do {
            try await swiftDataService.deleteConversations(date)
            try? await loadConversations()

            // Only clear the open conversation if it was actually deleted.
            if deletesSelectedConversation {
                selectedConversation = nil
                messages = []
            }
        } catch {
            // Deletion failed: keep the selection and surface the error so the
            // UI doesn't silently pretend the day was removed.
            withAnimation {
                conversationState = .error(message: "Failed to delete conversations: \(error.localizedDescription)")
            }
        }
    }
    
    
    /// Builds the OpenAI-compatible message history from persisted messages.
    /// Empty assistant placeholders (stopped or crashed generations) are
    /// skipped so they aren't sent as blank turns. Internal for unit tests.
    static func messageHistory(from messages: [MessageSD]) -> [ChatMessage] {
        messages
            .filter { !($0.role == "assistant" && $0.content.isEmpty) }
            .map { message in
                // Cached base64 data URL: re-encoding every historical image
                // on each turn was O(total image bytes) per prompt.
                let imageURL = message.imageDataURL.map { ImageURL(url: $0) }

                return ChatMessage(
                    role: message.role,
                    content: message.content,
                    image_url: imageURL
                )
            }
    }

    func create(_ conversation: ConversationSD) async throws {
        try await swiftDataService.createConversation(conversation)
    }
    
    func reloadConversation(_ conversation: ConversationSD) async throws {
        let (messages, selectedConversation) = try await (
            swiftDataService.fetchMessages(conversation.id),
            swiftDataService.getConversation(conversation.id)
        )
        
        DispatchQueue.main.async {
                self.messages = messages
                self.selectedConversation = selectedConversation
        }
    }
    
    func selectConversation(_ conversation: ConversationSD) async throws {
        try await reloadConversation(conversation)
    }
    
    func delete(_ conversation: ConversationSD) async throws {
        try await swiftDataService.deleteConversation(conversation)
        let fetchedConversations = try await swiftDataService.fetchConversations()
        DispatchQueue.main.async {
            self.selectedConversation = nil
            self.conversations = fetchedConversations
        }
    }
    
    @MainActor func stopGenerate() {
        // Cancel the generation task
        generationTask?.cancel()

        let target = streamingMessage ?? messages.last

        // Flush any remaining buffer content immediately to prevent memory leak
        if !currentMessageBuffer.isEmpty, let target {
            target.content += currentMessageBuffer.joined()
            currentMessageBuffer = []
        }

        // Record partial analytics for the stopped generation (AN-7) so the
        // footer shows what was produced instead of rendering empty.
        if let target, target.role == "assistant", !target.done {
            if let start = requestStartTime {
                target.totalTime = Date().timeIntervalSince(start)
            }
            if let usage = lastUsage {
                if let prompt = usage.prompt_tokens { target.promptTokens = prompt }
                if let completion = usage.completion_tokens { target.completionTokens = completion }
                if let total = usage.total_tokens { target.totalTokens = total }
            }
            if target.completionTokens == nil, let content = target.realContent, !content.isEmpty {
                target.completionTokens = max(1, content.count / 4)
            }
            Task(priority: .background) {
                try? await swiftDataService.updateMessage(target)
            }
        }

        // Finalize the message and reset state
        finalizeMessage()
    }

    /// Finalize the current message and reset streaming state
    /// This is called when stopping or when streaming completes
    @MainActor
    private func finalizeMessage() {
        // CRITICAL: Always reset state FIRST, before any other operations
        // This ensures the stop button ALWAYS reverts
        conversationState = .completed
        
        guard let lastMessage = streamingMessage ?? messages.last else {
            resetStreamingState()
            return
        }

        // Mark message as done if not already
        if !lastMessage.done {
            lastMessage.done = true
            lastMessage.error = false
            // Force SwiftUI to see the change by reassigning
            let currentMessages = messages
            messages = []
            messages = currentMessages

            // Save to disk asynchronously
            Task(priority: .background) {
                try? await swiftDataService.updateMessage(lastMessage)
            }
        }

        // Reset streaming state
        resetStreamingState()
    }
    
    @MainActor
    func sendPrompt(userPrompt: String, model: LanguageModelSD, image: Image? = nil, systemPrompt: String = "", trimmingMessageId: String? = nil) {
        guard userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 else { return }

        // Reset any previous streaming state before starting new request
        resetStreamingState()

        let conversation = selectedConversation ?? ConversationSD(name: userPrompt)
        conversation.updatedAt = Date.now
        conversation.model = model

        /// trim conversation if on edit mode
        if let trimmingMessageId = trimmingMessageId {
            conversation.messages = conversation.messages
                .sorted{$0.createdAt < $1.createdAt}
                .prefix(while: {$0.id.uuidString != trimmingMessageId})
        }

        /// add system prompt to very first message in the conversation
        if !systemPrompt.isEmpty && conversation.messages.isEmpty {
            let systemMessage = MessageSD(content: systemPrompt, role: "system")
            systemMessage.conversation = conversation
        }

        /// construct new message
        let userMessage = MessageSD(content: userPrompt, role: "user", image: image?.render()?.compressImageData())
        userMessage.conversation = conversation

        /// prepare message history for the provider (OpenAI-compatible).
        /// The freshly attached user message is already part of
        /// conversation.messages, so building history from the relationship
        /// yields exactly one copy of it (F-19: it used to be appended a
        /// second time, sending the prompt twice per turn).
        let messageHistory = Self.messageHistory(
            from: conversation.messages.sorted { $0.createdAt < $1.createdAt }
        )

        let assistantMessage = MessageSD(content: "", role: "assistant")
        assistantMessage.conversation = conversation
        streamingMessage = assistantMessage

        conversationState = .loading

        Task {
            do {
                try await swiftDataService.updateConversation(conversation)
                try await swiftDataService.createMessage(userMessage)
                try await swiftDataService.createMessage(assistantMessage)
                try await reloadConversation(conversation)
            } catch {
                // Setup failed before streaming started. Surface the error so the
                // UI leaves the loading state and the user can retry (F-20).
                // handleError is not used here: it flags messages.last, which may
                // not exist yet or may belong to a previous conversation.
                withAnimation {
                    conversationState = .error(message: "Failed to prepare conversation: \(error.localizedDescription)")
                }
                return
            }
            try? await loadConversations()

            // Get the appropriate provider based on model
            guard let provider = getProvider(for: model) else {
                await MainActor.run {
                    handleError("Unknown model provider")
                }
                return
            }

            // Check if provider is reachable
            guard await provider.reachable() else {
                await MainActor.run {
                    handleError("\(model.modelProvider?.displayName ?? "Provider") is not reachable")
                }
                return
            }

            // Track request start time for analytics
            let requestStart = Date()

            generationTask = Task { [weak self] in
                guard let self = self else { return }

                await MainActor.run {
                    self.requestStartTime = requestStart
                    self.hasReceivedFirstToken = false
                }

                do {
                    let stream = provider.chatStream(
                        model: model.name,
                        messages: messageHistory,
                        temperature: 0.0,
                        maxTokens: nil
                    )

                    for try await response in stream {
                        if Task.isCancelled {
                            break
                        }
                        await MainActor.run {
                            self.handleReceive(response, requestStart: requestStart)
                        }
                    }

                    // Stream completed normally - finalize message and calculate analytics
                    // Call directly on MainActor to ensure state updates propagate
                    await MainActor.run {
                        self.handleComplete(requestStart: requestStart)
                    }
                } catch {
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.handleError(error.localizedDescription)
                        }
                    }
                    // If cancelled, stopGenerate already called finalizeMessage
                }
            }
        }
    }

    // MARK: - Analytics (see ANALYTICS_REVIEW.md)

    /// Per-message analytics computed when a stream completes.
    struct Analytics {
        var totalTime: TimeInterval?
        var promptEvalTime: TimeInterval?
        var evalTime: TimeInterval?
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?
    }

    /// Computes one message's analytics, preferring server-reported counts
    /// and durations (usage) over client measurement and character-based
    /// estimates. Pure; internal for unit tests.
    static func computeAnalytics(
        usage: Usage?,
        promptCharacterCount: Int,
        completionCharacterCount: Int,
        requestStart: Date,
        firstTokenTime: Date?,
        completionTime: Date
    ) -> Analytics {
        var analytics = Analytics()

        // Tokens: server counts win; otherwise estimate ~4 chars per token
        // (a crude tokenizer proxy — the UI presents these as estimates).
        let promptTokens = usage?.prompt_tokens ?? max(1, promptCharacterCount / 4)
        let completionTokens = usage?.completion_tokens ?? max(1, completionCharacterCount / 4)
        analytics.promptTokens = promptTokens
        analytics.completionTokens = completionTokens
        analytics.totalTokens = usage?.total_tokens ?? (promptTokens + completionTokens)

        // Timing: server-reported durations win where present; client
        // timestamps fill the gaps (e.g. Swama reports only a total).
        let hasServerDurations = (usage?.prompt_eval_duration != nil)
            || (usage?.eval_duration != nil)
            || (usage?.total_duration != nil)
        if let usage, hasServerDurations {
            let total = usage.total_duration ?? completionTime.timeIntervalSince(requestStart)
            if let promptEval = usage.prompt_eval_duration {
                analytics.promptEvalTime = promptEval
                analytics.evalTime = usage.eval_duration ?? max(0, total - promptEval)
            } else if let evalDuration = usage.eval_duration {
                analytics.evalTime = evalDuration
                analytics.promptEvalTime = max(0, total - evalDuration)
            } else if let firstToken = firstTokenTime {
                // Total only: keep the client prompt/eval split, bounded by
                // the server total.
                let promptEval = firstToken.timeIntervalSince(requestStart)
                analytics.promptEvalTime = promptEval
                analytics.evalTime = max(0, total - promptEval)
            } else {
                analytics.promptEvalTime = 0
                analytics.evalTime = total
            }
            analytics.totalTime = total
        } else {
            let totalTime = completionTime.timeIntervalSince(requestStart)
            analytics.totalTime = totalTime
            if let firstToken = firstTokenTime {
                analytics.promptEvalTime = firstToken.timeIntervalSince(requestStart)
                analytics.evalTime = completionTime.timeIntervalSince(firstToken)
            } else {
                analytics.promptEvalTime = 0
                analytics.evalTime = totalTime
            }
        }
        return analytics
    }

    /// Characters sent as the prompt for `message`: every earlier turn in the
    /// conversation plus the current user turn (which may share its createdAt
    /// with the assistant placeholder — matched with <= and identity, not
    /// strict <). Image bytes are not counted: vision tokenization is
    /// model-specific, so image prompts undercount (AN-4). Internal for tests.
    static func promptCharacterCount(for message: MessageSD) -> Int {
        guard let conversation = message.conversation else { return 0 }
        return conversation.messages
            .filter { candidate in
                candidate.id != message.id
                    && candidate.createdAt <= message.createdAt
                    && !(candidate.role == "assistant" && candidate.content.isEmpty)
            }
            .reduce(0) { total, candidate in
                total + (candidate.realContent?.count ?? candidate.content.count)
            }
    }

    /// Handle successful stream completion - calculate analytics and finalize
    @MainActor
    func handleComplete(requestStart: Date) {
        guard let lastMessage = streamingMessage ?? messages.last else {
            finalizeMessage()
            return
        }

        // Flush any remaining content in the buffer immediately
        if !currentMessageBuffer.isEmpty {
            let bufferedContent = currentMessageBuffer.joined()
            lastMessage.content += bufferedContent
            currentMessageBuffer = []
        }

        let analytics = Self.computeAnalytics(
            usage: lastUsage,
            promptCharacterCount: Self.promptCharacterCount(for: lastMessage),
            completionCharacterCount: lastMessage.realContent?.count ?? 0,
            requestStart: requestStart,
            firstTokenTime: firstTokenTime,
            completionTime: Date()
        )
        lastMessage.totalTime = analytics.totalTime
        lastMessage.promptEvalTime = analytics.promptEvalTime
        lastMessage.evalTime = analytics.evalTime
        lastMessage.promptTokens = analytics.promptTokens
        lastMessage.completionTokens = analytics.completionTokens
        lastMessage.totalTokens = analytics.totalTokens

        lastMessage.error = false
        lastMessage.done = true

        // Force SwiftUI observation
        let currentMessages = messages
        messages = []
        messages = currentMessages

        Task(priority: .background) {
            try await swiftDataService.updateMessage(lastMessage)
        }

        // Finalize message and reset state
        finalizeMessage()
    }

    @MainActor
    func handleReceive(_ response: ChatCompletionResponse, requestStart: Date) {
        // Keep the latest server-reported usage (final chunk carries it).
        if let usage = response.usage {
            lastUsage = usage
        }

        // Handle streaming response - content can be in delta or message
        // Extract text content from ContentType enum
        let deltaContent = response.choices?.first?.delta?.content
        let messageContent = response.choices?.first?.message?.content

        let responseContent: String? = {
            if let delta = deltaContent {
                switch delta {
                case .string(let text):
                    return text.isEmpty ? nil : text
                case .array(let parts):
                    let text = parts.compactMap { $0.text }.joined()
                    return text.isEmpty ? nil : text
                }
            } else if let message = messageContent {
                switch message {
                case .string(let text):
                    return text.isEmpty ? nil : text
                case .array(let parts):
                    let text = parts.compactMap { $0.text }.joined()
                    return text.isEmpty ? nil : text
                }
            }
            return nil
        }()

        if let responseContent = responseContent, !responseContent.isEmpty {
            // Stamp "first token" on the first chunk that actually carries
            // content (AN-3: some providers lead with a role-only chunk,
            // which would overstate prompt eval time).
            if !hasReceivedFirstToken {
                firstTokenTime = Date()
                hasReceivedFirstToken = true
            }

            // Append to buffer array - O(1) instead of O(n) string concatenation
            currentMessageBuffer.append(responseContent)

            // Use weak self to prevent retain cycles in throttler
            throttler.throttle { [weak self] in
                guard let self = self else { return }
                // Write to the captured streaming message so content lands in
                // the right conversation even if the user switched away.
                guard let target = self.streamingMessage ?? self.messages.last else { return }
                // Join all buffered chunks at once - O(n) total instead of O(n²)
                target.content += self.currentMessageBuffer.joined()
                self.currentMessageBuffer = []
            }
        }
    }

    @MainActor
    private func handleError(_ errorMessage: String) {
        let target = streamingMessage ?? messages.last
        if let target {
            target.error = true
            target.done = false

            Task(priority: .background) {
                try? await swiftDataService.updateMessage(target)
            }
        }

        withAnimation {
            conversationState = .error(message: errorMessage)
        }

        // Clear streaming state so a later Stop can't flush stale chunks.
        // (finalizeMessage is not used here: it would reset the error state.)
        currentMessageBuffer = []
        streamingMessage = nil
        hasReceivedFirstToken = false
        generationTask = nil
    }

    /// Dismisses the error banner, if one is showing (F-35).
    @MainActor
    func dismissError() {
        if case .error = conversationState {
            withAnimation {
                conversationState = .completed
            }
        }
    }

    /// Get the appropriate model provider service for a given model
    private func getProvider(for model: LanguageModelSD) -> ModelProviderProtocol? {
        guard let provider = model.modelProvider else { return nil }

        switch provider {
        case .swama:
            return SwamaService.shared
        case .ollama:
            return OllamaService.shared
        case .appleFoundation:
            return AppleFoundationService.shared
        }
    }
}

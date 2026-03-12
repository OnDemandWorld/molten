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
#if os(macOS)
    private let throttler = Throttler(delay: 0.15)
#else
    private let throttler = Throttler(delay: 0.15)
#endif

    // Analytics tracking
    private var requestStartTime: Date?
    private var firstTokenTime: Date?
    private var hasReceivedFirstToken: Bool = false

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
    
    func deleteDailyConversations(_ date: Date) {
        Task {
            DispatchQueue.main.async { [self] in
                selectedConversation = nil
                messages = []
            }
            try? await swiftDataService.deleteConversations()
            try? await loadConversations()
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

        // Flush any remaining buffer content immediately to prevent memory leak
        if !currentMessageBuffer.isEmpty, let lastMessage = messages.last {
            let bufferedContent = currentMessageBuffer.joined()
            lastMessage.content += bufferedContent
            currentMessageBuffer = []
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
        
        guard let lastMessage = messages.last else {
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

        /// prepare message history for Swama (OpenAI-compatible)
        var messageHistory: [ChatMessage] = conversation.messages
            .sorted{$0.createdAt < $1.createdAt}
            .map { message in
                // Handle image if present
                var imageURL: ImageURL? = nil
                if let imageData = message.image {
                    let base64Image = imageData.base64EncodedString()
                    let dataURL = "data:image/jpeg;base64,\(base64Image)"
                    imageURL = ImageURL(url: dataURL)
                }

                return ChatMessage(
                    role: message.role,
                    content: message.content,
                    image_url: imageURL
                )
            }

        // Add the new user message to history
        var imageURL: ImageURL? = nil
        if let image = image?.render() {
            let base64Image = image.convertImageToBase64String()
            let dataURL = "data:image/jpeg;base64,\(base64Image)"
            imageURL = ImageURL(url: dataURL)
        }

        let newUserMessage = ChatMessage(
            role: "user",
            content: userPrompt,
            image_url: imageURL
        )

        messageHistory.append(newUserMessage)

        let assistantMessage = MessageSD(content: "", role: "assistant")
        assistantMessage.conversation = conversation

        conversationState = .loading

        Task {
            try await swiftDataService.updateConversation(conversation)
            try await swiftDataService.createMessage(userMessage)
            try await swiftDataService.createMessage(assistantMessage)
            try await reloadConversation(conversation)
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

    /// Handle successful stream completion - calculate analytics and finalize
    @MainActor
    private func handleComplete(requestStart: Date) {
        guard let lastMessage = messages.last else {
            finalizeMessage()
            return
        }

        // Flush any remaining content in the buffer immediately
        if !currentMessageBuffer.isEmpty {
            let bufferedContent = currentMessageBuffer.joined()
            lastMessage.content += bufferedContent
            currentMessageBuffer = []
        }

        // Calculate analytics
        let completionTime = Date()
        let totalTime = completionTime.timeIntervalSince(requestStart)
        lastMessage.totalTime = totalTime

        if let firstToken = firstTokenTime {
            let promptEvalTime = firstToken.timeIntervalSince(requestStart)
            lastMessage.promptEvalTime = promptEvalTime
            let evalTime = completionTime.timeIntervalSince(firstToken)
            lastMessage.evalTime = evalTime
        } else {
            lastMessage.evalTime = totalTime
            lastMessage.promptEvalTime = 0
        }

        // Estimate token counts
        if lastMessage.completionTokens == nil, let content = lastMessage.realContent {
            lastMessage.completionTokens = max(1, content.count / 4)
        }

        if lastMessage.promptTokens == nil {
            let conversation = lastMessage.conversation
            let allMessages = conversation?.messages.sorted(by: { $0.createdAt < $1.createdAt }) ?? []
            let previousMessages = allMessages.filter { $0.createdAt < lastMessage.createdAt }
            let totalPromptChars = previousMessages.reduce(0) { total, msg in
                total + (msg.realContent?.count ?? msg.content.count)
            }
            lastMessage.promptTokens = max(1, totalPromptChars / 4)
        }

        if let prompt = lastMessage.promptTokens, let completion = lastMessage.completionTokens {
            lastMessage.totalTokens = prompt + completion
        } else if let total = lastMessage.totalTokens {
            if lastMessage.promptTokens == nil {
                lastMessage.promptTokens = max(1, total / 3)
            }
            if lastMessage.completionTokens == nil {
                lastMessage.completionTokens = max(1, total - (lastMessage.promptTokens ?? 0))
            }
        }

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
    private func handleReceive(_ response: ChatCompletionResponse, requestStart: Date) {
        if messages.isEmpty {
            return
        }

        // Track first token time for analytics
        if !hasReceivedFirstToken {
            firstTokenTime = Date()
            hasReceivedFirstToken = true
        }

        // Update token counts from usage if available
        if let usage = response.usage {
            let lastIndex = messages.count - 1
            if lastIndex >= 0 && lastIndex < messages.count {
                let message = messages[lastIndex]
                if let promptTokens = usage.prompt_tokens {
                    message.promptTokens = promptTokens
                }
                if let completionTokens = usage.completion_tokens {
                    message.completionTokens = completionTokens
                }
                if let totalTokens = usage.total_tokens {
                    message.totalTokens = totalTokens
                }
            }
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
            // Append to buffer array - O(1) instead of O(n) string concatenation
            currentMessageBuffer.append(responseContent)

            // Use weak self to prevent retain cycles in throttler
            throttler.throttle { [weak self] in
                guard let self = self else { return }
                let lastIndex = self.messages.count - 1
                if lastIndex >= 0 && lastIndex < self.messages.count {
                    // Join all buffered chunks at once - O(n) total instead of O(n²)
                    let bufferedContent = self.currentMessageBuffer.joined()
                    self.messages[lastIndex].content += bufferedContent
                    self.currentMessageBuffer = []
                }
            }
        }
    }

    @MainActor
    private func handleError(_ errorMessage: String) {
        guard let lastMesasge = messages.last else { return }
        lastMesasge.error = true
        lastMesasge.done = false

        Task(priority: .background) {
            try? await swiftDataService.updateMessage(lastMesasge)
        }

        withAnimation {
            conversationState = .error(message: errorMessage)
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

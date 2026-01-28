//
//  OllamaService.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 09/12/2023.
//

import Foundation
@preconcurrency import Combine
import OllamaKit

final class OllamaService: @unchecked Sendable, ModelProviderProtocol {
    static let shared = OllamaService()
    
    private var ollamaKit: OllamaKit
    private var isConfigured: Bool = false
    private var isUsingDefaultLocalhost: Bool = true // Track if using default vs user-configured URL
    
    init() {
        ollamaKit = OllamaKit(baseURL: URL(string: "http://localhost:11434")!)
        initEndpoint()
    }
    
    func initEndpoint(url: String? = nil, bearerToken: String? = "okki") {
        let localStorageUrl = UserDefaults.standard.string(forKey: "ollamaUri")
        let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
        
        // Priority: explicit url param > stored URL > default localhost
        let configuredUrl = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? 
                               localStorageUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If user explicitly configured a URL, use it
        if let ollamaUrl = configuredUrl, !ollamaUrl.isEmpty {
            var finalUrl = ollamaUrl
            if !finalUrl.contains("http") {
                finalUrl = "http://" + finalUrl
            }
            
            if let url = URL(string: finalUrl) {
                ollamaKit = OllamaKit(baseURL: url, bearerToken: bearerToken)
                isConfigured = true
                isUsingDefaultLocalhost = false // User explicitly configured URL
                return
            }
        }
        
        // No explicit config - use default localhost (common case for local Ollama)
        // Mark as "default" so we can use different backoff strategy
        ollamaKit = OllamaKit(baseURL: URL(string: "http://localhost:11434")!)
        isConfigured = true // Still configured, just using default
        isUsingDefaultLocalhost = true
    }
    
    /// Returns true if using default localhost (vs user-configured URL)
    /// Used to determine backoff strategy
    var usingDefaultLocalhost: Bool {
        isUsingDefaultLocalhost
    }
    
    func getModels() async throws -> [LanguageModel] {
        let response = try await ollamaKit.models()
        let models = response.models.map{
            LanguageModel(
                name: $0.name,
                provider: .ollama,
                imageSupport: $0.details.families?.contains(where: { $0 == "clip" || $0 == "mllama" }) ?? false
            )
        }
        return models
    }
    
    func reachable() async -> Bool {
        // Don't poll if not configured
        guard isConfigured else { return false }
        
        // Add timeout to prevent long waits when Ollama isn't running
        return await withTimeout(seconds: 2.0) { [self] in
            await self.ollamaKit.reachable()
        } ?? false
    }
    
    /// Helper to add timeout to async Bool operations
    private func withTimeout(seconds: TimeInterval, operation: @escaping () async -> Bool) async -> Bool? {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
    
    func chatStream(
        model: String,
        messages: [ChatMessage],
        temperature: Double?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<ChatCompletionResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Convert ChatMessage format to Ollama format
                // Use the actual OllamaKit types: OKChatRequestData and OKChatRequestData.Message
                let ollamaMessages = messages.compactMap { chatMessage -> OKChatRequestData.Message? in
                    guard let role = chatMessage.role else { return nil }
                    
                    // Extract content from ChatMessage
                    let content: String
                    if let chatContent = chatMessage.content {
                        switch chatContent {
                        case .string(let text):
                            content = text
                        case .array(let parts):
                            // For multimodal, extract text parts only (Ollama may not support images in streaming)
                            content = parts.compactMap { $0.text }.joined(separator: " ")
                        }
                    } else {
                        content = ""
                    }
                    
                    // Map role to Ollama role enum
                    let messageRole: OKChatRequestData.Message.Role
                    switch role.lowercased() {
                    case "user":
                        messageRole = .user
                    case "assistant":
                        messageRole = .assistant
                    case "system":
                        messageRole = .system
                    default:
                        messageRole = .user
                    }
                    
                    return OKChatRequestData.Message(role: messageRole, content: content)
                }
                
                // Create options if needed
                var options: OKCompletionOptions? = nil
                if temperature != nil || maxTokens != nil {
                    options = OKCompletionOptions(
                        temperature: temperature.map { Float($0) },
                        numPredict: maxTokens
                    )
                }
                
                // Create request
                var request = OKChatRequestData(model: model, messages: ollamaMessages)
                request.options = options
                
                // Convert Combine Publisher to AsyncThrowingStream
                // OllamaKit returns AnyPublisher<OKChatResponse, Error>
                let publisher = ollamaKit.chat(data: request)
                
                // Use a class to hold the cancellable to avoid Sendable issues
                final class CancellableHolder: @unchecked Sendable {
                    var cancellable: AnyCancellable?
                }
                
                let holder = CancellableHolder()
                
                // Convert directly to ChatCompletionResponse inside the sink
                // to avoid Sendable issues with OKChatResponse
                holder.cancellable = publisher.sink(
                    receiveCompletion: { completion in
                        switch completion {
                        case .finished:
                            continuation.finish()
                        case .failure(let error):
                            continuation.finish(throwing: error)
                        }
                        holder.cancellable?.cancel()
                    },
                    receiveValue: { response in
                        // Convert Ollama response to ChatCompletionResponse format
                        let chatResponse = ChatCompletionResponse(
                            id: response.model,
                            object: "chat.completion.chunk",
                            created: nil,
                            model: response.model,
                            choices: [
                                Choice(
                                    index: 0,
                                    message: nil,
                                    delta: ChatMessage(
                                        role: response.message?.role.rawValue ?? "assistant",
                                        content: response.message?.content ?? "",
                                        image_url: nil
                                    ),
                                    finish_reason: (response.done == true) ? "stop" : nil
                                )
                            ],
                            usage: nil
                        )
                        
                        continuation.yield(chatResponse)
                        
                        if response.done == true {
                            continuation.finish()
                        }
                    }
                )
                
                continuation.onTermination = { @Sendable _ in
                    holder.cancellable?.cancel()
                }
            }
        }
    }
}

//
//  OllamaService.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 09/12/2023.
//

import Foundation
@preconcurrency import Combine
import OllamaKit

// Helper class to hold Cancellable for Combine to AsyncStream conversion
// Defined outside to avoid creating new type on each stream call
private final class CancellableHolder: @unchecked Sendable {
    var cancellable: AnyCancellable?
}

final class OllamaService: @unchecked Sendable, ModelProviderProtocol {
    static let shared = OllamaService()
    
    private var ollamaKit: OllamaKit
    private var isConfigured: Bool = false
    private var isUsingDefaultLocalhost: Bool = true // Track if using default vs user-configured URL
    private var currentBaseURL = URL(string: "http://localhost:11434")!
    private var currentToken: String?
    
    init() {
        ollamaKit = OllamaKit(baseURL: URL(string: "http://localhost:11434")!)
        initEndpoint()
    }
    
    func initEndpoint(url: String? = nil, bearerToken: String? = nil) {
        // Shared resolution (URL priority, empty-disables, F-44/F-48 token
        // semantics) lives in ProviderEndpointResolver so Ollama and Swama
        // can't drift apart.
        let endpoint = ProviderEndpointResolver.resolve(
            url: url,
            token: bearerToken,
            urlKey: "ollamaUri",
            tokenKey: "ollamaBearerToken",
            defaultLocalhost: URL(string: "http://localhost:11434")!
        )
        ollamaKit = OllamaKit(baseURL: endpoint.baseURL, bearerToken: endpoint.bearerToken)
        currentBaseURL = endpoint.baseURL
        currentToken = endpoint.bearerToken
        isConfigured = !endpoint.disabled
        isUsingDefaultLocalhost = endpoint.usingDefaultLocalhost
    }

    /// X1: context window from Ollama /api/show (model_info "<arch>.context_length").
    func contextLength(model: String) async -> Int? {
        guard isConfigured else { return nil }
        var request = URLRequest(url: currentBaseURL.appendingPathComponent("api/show"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let currentToken { request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["name": model])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = json["model_info"] as? [String: Any] else { return nil }
        for (key, value) in info where key.hasSuffix(".context_length") {
            if let length = value as? Int { return length }
            if let number = value as? NSNumber { return number.intValue }
        }
        return nil
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
                    continuation.yield(Self.mapResponse(response))

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

    /// Maps an OllamaKit chat response to the shared ChatCompletionResponse,
    /// carrying Ollama's authoritative eval statistics from the final chunk
    /// over as Usage (AN-1: they were previously dropped).
    static func mapResponse(_ response: OKChatResponse) -> ChatCompletionResponse {
        ChatCompletionResponse(
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
            usage: usageFromOllama(
                done: response.done,
                promptEvalCount: response.promptEvalCount,
                promptEvalDuration: response.promptEvalDuration,
                evalCount: response.evalCount,
                evalDuration: response.evalDuration,
                totalDuration: response.totalDuration
            )
        )
    }

    /// Builds Usage from Ollama's final-chunk counters (nanoseconds → seconds).
    /// Non-final chunks carry no statistics and map to nil. Internal for tests.
    static func usageFromOllama(
        done: Bool?,
        promptEvalCount: Int?,
        promptEvalDuration: Int?,
        evalCount: Int?,
        evalDuration: Int?,
        totalDuration: Int?
    ) -> Usage? {
        guard done == true else { return nil }

        func seconds(_ nanos: Int?) -> Double? {
            nanos.map { Double($0) / 1_000_000_000 }
        }
        let total: Int? = {
            guard let prompt = promptEvalCount, let completion = evalCount else { return nil }
            return prompt + completion
        }()

        return Usage(
            prompt_tokens: promptEvalCount,
            completion_tokens: evalCount,
            total_tokens: total,
            prompt_eval_duration: seconds(promptEvalDuration),
            eval_duration: seconds(evalDuration),
            total_duration: seconds(totalDuration),
            response_tokens_per_second: nil
        )
    }
}

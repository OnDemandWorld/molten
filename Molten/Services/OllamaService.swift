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
    
    init() {
        ollamaKit = OllamaKit(baseURL: URL(string: "http://localhost:11434")!)
        initEndpoint()
    }
    
    func initEndpoint(url: String? = nil, bearerToken: String? = "okki") {
        let defaultUrl = "http://localhost:11434"
        let localStorageUrl = UserDefaults.standard.string(forKey: "ollamaUri")
        let bearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken")
        if var ollamaUrl = [localStorageUrl, defaultUrl].compactMap({$0}).filter({$0.count > 0}).first {
            if !ollamaUrl.contains("http") {
                ollamaUrl = "http://" + ollamaUrl
            }
            
            if let url = URL(string: ollamaUrl) {
                ollamaKit =  OllamaKit(baseURL: url, bearerToken: bearerToken)
                return
            }
        }
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
        return await ollamaKit.reachable()
    }
    
    func chatStream(
        model: String,
        messages: [ChatMessage],
        temperature: Double?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<ChatCompletionResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
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
                    
                    // Convert Publisher to AsyncThrowingStream
                    // Use a class to hold the cancellable to avoid Sendable issues
                    final class CancellableHolder: @unchecked Sendable {
                        var cancellable: AnyCancellable?
                    }
                    
                    let stream = AsyncThrowingStream<OKChatResponse, Error> { continuation in
                        let holder = CancellableHolder()
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
                                continuation.yield(response)
                            }
                        )
                        
                        continuation.onTermination = { @Sendable _ in
                            holder.cancellable?.cancel()
                        }
                    }
                    
                    for try await response in stream {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        
                        // Convert Ollama response to ChatCompletionResponse format
                        // OKChatResponse doesn't have an id field, so we'll use the model name
                        let chatResponse = ChatCompletionResponse(
                            id: response.model, // Use model as ID since OKChatResponse doesn't have id
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
                            return
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

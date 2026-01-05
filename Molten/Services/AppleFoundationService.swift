//
//  AppleFoundationService.swift
//  Molten
//
//  Service for Apple Foundation Models (on-device AI)
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@available(macOS 26.0, *)
final class AppleFoundationService: @unchecked Sendable, ModelProviderProtocol {
    static let shared = AppleFoundationService()
    
    private init() {}
    
    func reachable() async -> Bool {
        #if canImport(FoundationModels)
        // FoundationModels is available on supported devices
        // Check if we can create a session
        _ = LanguageModelSession()
        // If we can create a session, it's available
        return true
        #else
        return false
        #endif
    }
    
    func getModels() async throws -> [LanguageModel] {
        #if canImport(FoundationModels)
        // Apple Foundation Models provides a single on-device model
        // The model name/identifier may vary, but we'll use a standard identifier
        return [
            LanguageModel(
                name: "apple-foundation-model",
                provider: .appleFoundation,
                imageSupport: false // Check FoundationModels docs for image support
            )
        ]
        #else
        throw NSError(domain: "AppleFoundationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "FoundationModels framework not available"])
        #endif
    }
    
    func chatStream(
        model: String,
        messages: [ChatMessage],
        temperature: Double?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<ChatCompletionResponse, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                #if canImport(FoundationModels)
                do {
                    let session = LanguageModelSession()
                        
                        // Convert messages to a single prompt
                        // FoundationModels uses a simple prompt interface
                        let prompt = messages.compactMap { message -> String? in
                            guard let role = message.role, let content = message.content else { return nil }
                            
                            let contentText: String
                            switch content {
                            case .string(let text):
                                contentText = text
                            case .array(let parts):
                                contentText = parts.compactMap { $0.text }.joined(separator: " ")
                            }
                            
                            // Format as conversation
                            switch role.lowercased() {
                            case "user":
                                return "User: \(contentText)"
                            case "assistant":
                                return "Assistant: \(contentText)"
                            case "system":
                                return "System: \(contentText)"
                            default:
                                return contentText
                            }
                        }.joined(separator: "\n\n")
                        
                        // Get the last user message for the actual prompt
                        let lastUserMessage = messages.last { $0.role?.lowercased() == "user" }
                        let actualPrompt = lastUserMessage?.content?.stringValue ?? prompt
                        
                        // Stream response from FoundationModels
                        // Note: FoundationModels may not support streaming directly
                        // We'll simulate streaming by chunking the response
                        let result = try await session.respond(to: actualPrompt)
                        
                        // Split response into chunks to simulate streaming
                        // LanguageModelSession.Response<String> - extract the string value
                        // The Response type wraps the actual string value
                        // Use reflection to find the actual string value
                        let text: String
                        let mirror = Mirror(reflecting: result)
                        if let textProperty = mirror.children.first(where: { $0.label == "text" || $0.label == "content" || $0.label == "value" || $0.label == "result" })?.value as? String {
                            text = textProperty
                        } else if let firstChild = mirror.children.first?.value as? String {
                            text = firstChild
                        } else {
                            // Last resort: convert to string representation
                            text = String(describing: result)
                        }
                    let chunkSize = 10 // Characters per chunk
                    var currentIndex = text.startIndex
                    
                    while currentIndex < text.endIndex {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        
                        let endIndex = text.index(currentIndex, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                        let chunk = String(text[currentIndex..<endIndex])
                        
                        let chatResponse = ChatCompletionResponse(
                            id: UUID().uuidString,
                            object: "chat.completion.chunk",
                            created: nil,
                            model: model,
                            choices: [
                                Choice(
                                    index: 0,
                                    message: nil,
                                    delta: ChatMessage(
                                        role: "assistant",
                                        content: chunk,
                                        image_url: nil
                                    ),
                                    finish_reason: endIndex >= text.endIndex ? "stop" : nil
                                )
                            ],
                            usage: nil
                        )
                        
                        continuation.yield(chatResponse)
                        
                        // Small delay to simulate streaming
                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                        
                        currentIndex = endIndex
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                #else
                continuation.finish(throwing: NSError(domain: "AppleFoundationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "FoundationModels framework not available"]))
                #endif
            }
        }
    }
}

// Helper extension for ContentType
extension ContentType {
    var stringValue: String {
        switch self {
        case .string(let text):
            return text
        case .array(let parts):
            return parts.compactMap { $0.text }.joined(separator: " ")
        }
    }
}


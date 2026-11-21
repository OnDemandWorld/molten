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
        // Reflect real availability (Apple Intelligence enabled + model ready)
        // instead of always returning true. Also avoids allocating a session
        // on every reachability poll. Same check `respond(prompt:)` uses.
        return SystemLanguageModel.default.isAvailable
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
            let task = Task {
                #if canImport(FoundationModels)
                do {
                    // K-R4 on Apple models: system messages (user system prompt
                    // + Knowledge grounding) become the session's instructions.
                    // AFM follows instructions reliably; "System:" text pasted
                    // into a flat user turn was ignored, so RAG answers didn't
                    // use the sources.
                    let (instructions, turns) = Self.splitMessages(messages)
                    let session = LanguageModelSession(instructions: instructions)

                    // Send the FULL conversation history so multi-turn context
                    // is preserved (F-26: previously only the last user message
                    // was sent, making chat stateless).
                    let prompt = Self.constructPrompt(from: turns)

                    // FoundationModels has no token streaming — simulate it by
                    // chunking the response.
                    let result = try await session.respond(to: prompt)
                    let text = result.content
                    // 40 chars/chunk keeps the streaming feel while cutting
                    // per-chunk overhead (was 10, i.e. 4x more yields/tasks).
                    let chunkSize = 40 // Characters per chunk
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
                } catch let error as LanguageModelSession.GenerationError {
                    // The 4096-token window is shared by instructions, prompt
                    // and output — long chats with Knowledge attached can
                    // exceed it. Give an actionable message instead of the
                    // framework's generic error.
                    let message: String
                    switch error {
                    case .exceededContextWindowSize:
                        message = "This chat is too long for Apple's on-device model. Start a new conversation or detach the knowledge base."
                    default:
                        message = error.localizedDescription
                    }
                    continuation.finish(throwing: NSError(
                        domain: "AppleFoundationService", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: message]))
                } catch {
                    continuation.finish(throwing: error)
                }
                #else
                continuation.finish(throwing: NSError(domain: "AppleFoundationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "FoundationModels framework not available"]))
                #endif
            }

            // Cancel the producer task when the consumer stops consuming —
            // e.g. the user tapped Stop. Mirrors the lifecycle handling in
            // OllamaService.chatStream. The in-loop Task.isCancelled check
            // stops chunk emission; structured cancellation propagates into
            // the awaited session.respond(to:).
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// One-shot completion for in-app features (e.g. start-page prompt
    /// suggestions) — no streaming simulation. Returns nil when the
    /// on-device model is unavailable or generation fails, so callers can
    /// fall back gracefully. Everything runs locally via FoundationModels.
    func respond(prompt: String, instructions: String? = nil) async -> String? {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return nil }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Splits system messages (user system prompt + Knowledge grounding)
    /// from the conversation turns. Systems become session instructions;
    /// the rest is the prompt transcript. Internal for unit tests.
    static func splitMessages(_ messages: [ChatMessage]) -> (instructions: String?, turns: [ChatMessage]) {
        let systems = messages
            .filter { $0.role?.lowercased() == "system" }
            .compactMap { $0.content?.textContent }
            .filter { !$0.isEmpty }
        let turns = messages.filter { $0.role?.lowercased() != "system" }
        return (systems.isEmpty ? nil : systems.joined(separator: "\n\n"), turns)
    }

    /// Builds a single prompt string from the full message history, labeling
    /// each turn by role. Internal so unit tests can cover prompt assembly.
    static func constructPrompt(from messages: [ChatMessage]) -> String {
        messages.compactMap { message -> String? in
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


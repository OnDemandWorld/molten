//
//  SwamaService.swift
//  Molten
//
//  Created for Swama integration
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "network")

// MARK: - OpenAI Compatible API Models
struct OpenAICompatibleModelsResponse: Codable {
    let data: [ModelData]
    let object: String
}

struct ModelData: Codable {
    let id: String
    let object: String
    let created: Int?
    let owned_by: String?
}

// MARK: - SwamaService
final class SwamaService: @unchecked Sendable, ModelProviderProtocol {
    static let shared = SwamaService()
    
    private var baseURL: URL
    private var apiKey: String?
    private var isConfigured: Bool = false
    private var isUsingDefaultLocalhost: Bool = true // Track if using default vs user-configured URL
    
    init() {
        baseURL = URL(string: "http://localhost:28100")!
        initEndpoint()
    }
    
    func initEndpoint(url: String? = nil, apiKey: String? = nil) {
        // Shared resolution (URL priority, empty-disables, token semantics)
        // lives in ProviderEndpointResolver so Ollama and Swama can't drift.
        let endpoint = ProviderEndpointResolver.resolve(
            url: url,
            token: apiKey,
            urlKey: "swamaUri",
            tokenKey: "swamaApiKey",
            defaultLocalhost: URL(string: "http://localhost:28100")!
        )
        baseURL = endpoint.baseURL
        self.apiKey = endpoint.bearerToken
        isConfigured = !endpoint.disabled
        isUsingDefaultLocalhost = endpoint.usingDefaultLocalhost
    }
    
    /// Returns true if using default localhost (vs user-configured URL)
    /// Used to determine backoff strategy
    var usingDefaultLocalhost: Bool {
        isUsingDefaultLocalhost
    }

    // MARK: - Request timeouts (F-42)
    // URLRequest.timeoutInterval bounds the wait for data; its practical
    // effect on long-running or stalled streams depends on the loading
    // system and remains to be verified on device. No
    // timeoutIntervalForResource override is set, so legitimate long
    // generations are not capped by a total lifetime limit.
    static let modelsTimeout: TimeInterval = 15
    static let streamStartTimeout: TimeInterval = 120
    static let completionTimeout: TimeInterval = 300

    /// Builds an authenticated request against the configured base URL.
    /// Internal so unit tests can verify method/timeout/header wiring.
    func makeRequest(path: String, method: String = "GET", timeout: TimeInterval, accept: String? = nil) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func getModels() async throws -> [LanguageModel] {
        let request = makeRequest(path: "/v1/models", timeout: Self.modelsTimeout)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "SwamaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models"])
        }
        
        let modelsResponse = try JSONDecoder().decode(OpenAICompatibleModelsResponse.self, from: data)
        
        // Map to LanguageModel - Swama models may support images if they're vision models
        // Common vision model names in Swama: gemma3, qwen3 (some variants)
        return modelsResponse.data.map { modelData in
            let modelName = modelData.id.lowercased()
            let imageSupport = modelName.contains("gemma") || 
                              modelName.contains("vision") || 
                              modelName.contains("llava") ||
                              modelName.contains("qwen") // Some Qwen models support vision
            
            return LanguageModel(
                name: modelData.id,
                provider: .swama,
                imageSupport: imageSupport
            )
        }
    }
    
    func reachable() async -> Bool {
        // Don't poll if not configured
        guard isConfigured else { return false }
        
        let url = baseURL.appendingPathComponent("/v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0
        
        // Add API key if available
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
    
    // MARK: - Chat Completion (Streaming)
    func chatStream(
        model: String,
        messages: [ChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) -> AsyncThrowingStream<ChatCompletionResponse, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                var request = makeRequest(
                    path: "/v1/chat/completions",
                    method: "POST",
                    timeout: Self.streamStartTimeout,
                    accept: "text/event-stream"
                )

                let requestBody = ChatCompletionRequest(
                    model: model,
                    messages: messages,
                    temperature: temperature,
                    max_tokens: maxTokens,
                    stream: true
                )
                
                do {
                    request.httpBody = try JSONEncoder().encode(requestBody)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        logger.error("SwamaService: invalid HTTP response")
                        continuation.finish(throwing: NSError(domain: "SwamaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]))
                        return
                    }

                    guard (200...299).contains(httpResponse.statusCode) else {
                        logger.error("SwamaService: HTTP error status: \(httpResponse.statusCode)")
                        continuation.finish(throwing: NSError(domain: "SwamaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start chat stream: HTTP \(httpResponse.statusCode)"]))
                        return
                    }

                    // SSE is line-based. Accumulate bytes and split on
                    // newlines as they arrive — each byte is looked at only
                    // once (O(n) total, no whole-buffer re-scans), and the
                    // buffer holds at most one partial line. The 1MB cap
                    // bounds memory if a server never sends a newline;
                    // bytes.lines can't be used here because it buffers an
                    // entire line with no length limit.
                    var buffer = Data()
                    let maxBufferSize = 1024 * 1024 // 1MB safety limit per line

                    // Handles one complete line. Returns false on [DONE],
                    // meaning the stream should end.
                    let handleLine: (String) -> Bool = { line in
                        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

                        // Skip empty lines (SSE event separators) and metadata
                        if trimmedLine.isEmpty
                            || trimmedLine.hasPrefix("event:")
                            || trimmedLine.hasPrefix("id:")
                            || trimmedLine.hasPrefix(":") {
                            return true
                        }

                        // Process SSE format: "data: {...}" or "data: [DONE]"
                        guard trimmedLine.hasPrefix("data: ") else { return true }
                        let jsonString = String(trimmedLine.dropFirst(6))

                        if jsonString == "[DONE]" {
                            return false
                        }

                        if let jsonData = jsonString.data(using: .utf8) {
                            do {
                                let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: jsonData)
                                continuation.yield(response)
                            } catch {
                                logger.error("SwamaService: failed to decode SSE response: \(error.localizedDescription, privacy: .private)")
                            }
                        }
                        return true
                    }

                    for try await byte in bytes {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }

                        if byte == 10 { // \n — line complete
                            let lineData = buffer
                            buffer = Data()
                            if let line = String(data: lineData, encoding: .utf8),
                               !handleLine(line) {
                                continuation.finish()
                                return
                            }
                        } else {
                            buffer.append(byte)
                            if buffer.count > maxBufferSize {
                                logger.warning("SwamaService: SSE line exceeded 1MB limit; discarding")
                                buffer = Data()
                            }
                        }
                    }
                    // Flush a trailing line that arrived without a final newline.
                    if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                        _ = handleLine(line)
                    }
                    continuation.finish()
                } catch {
                    logger.error("SwamaService: stream error: \(error.localizedDescription, privacy: .private)")
                    continuation.finish(throwing: error)
                }
            }

            // Cancel the producer task (and its URLSession request) when the
            // consumer stops consuming — e.g. the user tapped Stop. Mirrors the
            // lifecycle handling in OllamaService.chatStream.
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
    
    // MARK: - Chat Completion (Non-streaming)
    func chat(
        model: String,
        messages: [ChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) async throws -> ChatCompletionResponse {
        var request = makeRequest(
            path: "/v1/chat/completions",
            method: "POST",
            timeout: Self.completionTimeout
        )

        let requestBody = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: maxTokens,
            stream: false
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "SwamaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get chat completion"])
        }
        
        return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    }
}


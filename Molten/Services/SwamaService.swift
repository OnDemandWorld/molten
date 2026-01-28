//
//  SwamaService.swift
//  Molten
//
//  Created for Swama integration
//

import Foundation

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
        let localStorageUrl = UserDefaults.standard.string(forKey: "swamaUri")
        let storedApiKey = UserDefaults.standard.string(forKey: "swamaApiKey")
        
        // Priority: explicit url param > stored URL > default localhost
        let configuredUrl = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? 
                           localStorageUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If user explicitly configured a URL, use it
        if let swamaUrl = configuredUrl, !swamaUrl.isEmpty {
            var finalUrl = swamaUrl
            if !finalUrl.contains("http") {
                finalUrl = "http://" + finalUrl
            }
            
            if let url = URL(string: finalUrl) {
                baseURL = url
                self.apiKey = apiKey ?? storedApiKey
                isConfigured = true
                isUsingDefaultLocalhost = false // User explicitly configured URL
                return
            }
        }
        
        // No explicit config - use default localhost (common case for local Swama)
        baseURL = URL(string: "http://localhost:28100")!
        self.apiKey = apiKey ?? storedApiKey
        isConfigured = true // Still configured, just using default
        isUsingDefaultLocalhost = true
    }
    
    /// Returns true if using default localhost (vs user-configured URL)
    /// Used to determine backoff strategy
    var usingDefaultLocalhost: Bool {
        isUsingDefaultLocalhost
    }
    
    func getModels() async throws -> [LanguageModel] {
        let url = baseURL.appendingPathComponent("/v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
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
            Task {
                let url = baseURL.appendingPathComponent("/v1/chat/completions")
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                
                if let apiKey = apiKey {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }
                
                let requestBody = ChatCompletionRequest(
                    model: model,
                    messages: messages,
                    temperature: temperature,
                    max_tokens: maxTokens,
                    stream: true
                )
                
                do {
                    request.httpBody = try JSONEncoder().encode(requestBody)
                    
                    // Debug: Log request details
                    print("SwamaService: Sending request to \(url)")
                    if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                        print("SwamaService: Request body: \(bodyString)")
                    }
                    
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("SwamaService: Invalid HTTP response")
                        continuation.finish(throwing: NSError(domain: "SwamaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"]))
                        return
                    }
                    
                    print("SwamaService: HTTP Status: \(httpResponse.statusCode)")
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        print("SwamaService: HTTP error status: \(httpResponse.statusCode)")
                        continuation.finish(throwing: NSError(domain: "SwamaService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to start chat stream: HTTP \(httpResponse.statusCode)"]))
                        return
                    }
                    
                    print("SwamaService: Stream started, reading bytes...")
                    var buffer = Data()
                    var lineCount = 0
                    var responseCount = 0
                    
                    for try await byte in bytes {
                        if Task.isCancelled {
                            continuation.finish()
                            return
                        }
                        
                        buffer.append(byte)
                        
                        // Process complete lines (ending with \n or \r\n)
                        while let newlineIndex = buffer.firstIndex(of: 10) { // 10 is \n
                            let lineData = buffer.prefix(upTo: newlineIndex)
                            buffer.removeSubrange(..<buffer.index(after: newlineIndex))
                            
                            if let line = String(data: lineData, encoding: .utf8) {
                                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                lineCount += 1
                                
                                // Skip empty lines
                                if trimmedLine.isEmpty {
                                    continue
                                }
                                
                                // Process SSE format: "data: {...}" or "data: [DONE]"
                                if trimmedLine.hasPrefix("data: ") {
                                    let jsonString = String(trimmedLine.dropFirst(6))
                                    
                                    if jsonString == "[DONE]" {
                                        continuation.finish()
                                        return
                                    }
                                    
                                    if let jsonData = jsonString.data(using: .utf8) {
                                        do {
                                            let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: jsonData)
                                            responseCount += 1
                                            continuation.yield(response)
                                        } catch {
                                            print("SwamaService: Failed to decode SSE response: \(error.localizedDescription)")
                                            continue
                                        }
                                    }
                                } else if trimmedLine.hasPrefix("event:") || trimmedLine.hasPrefix("id:") {
                                    // Skip SSE metadata lines
                                    continue
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    print("SwamaService: Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
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
        let url = baseURL.appendingPathComponent("/v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
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


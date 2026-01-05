//
//  ModelProviderProtocol.swift
//  Molten
//
//  Protocol for unified model provider interface
//
//  This file defines the core protocol that all model providers must implement,
//  along with shared API types used across all providers. This abstraction allows
//  Molten to support multiple backends (Ollama, Swama, Apple Foundation Models)
//  through a unified interface.
//
//  Created for Molten v1.0.0
//

import Foundation

// MARK: - Shared API Types

/// Represents an image URL in OpenAI-compatible format
/// Used for multimodal messages (text + image)
struct ImageURL: Codable {
    let url: String
}

/// Represents a content part in a multimodal message
/// Can be either text or image content
struct ContentPart: Codable {
    let type: String
    var text: String?
    var image_url: ImageURL?
}

/// Represents message content that can be either a simple string
/// or an array of content parts (for multimodal messages)
/// This enum handles both formats used by OpenAI-compatible APIs
enum ContentType: Codable {
    case string(String)
    case array([ContentPart])
    
    /// Custom decoder to handle both string and array formats
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ContentPart].self) {
            self = .array(array)
        } else {
            throw DecodingError.typeMismatch(ContentType.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Content must be String or Array"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        }
    }
}

/// Represents a chat message in OpenAI-compatible format
/// Used for both requests and responses across all providers
struct ChatMessage: Codable {
    let role: String?  // "user", "assistant", "system"
    var content: ContentType?  // Can be string or array of parts
    var image_url: ImageURL?  // For backward compatibility
    
    enum CodingKeys: String, CodingKey {
        case role, content
        case image_url
    }
    
    init(role: String, content: String, image_url: ImageURL?) {
        self.role = role
        if let image_url = image_url {
            // Use array format for multimodal messages (OpenAI-compatible)
            self.content = .array([
                ContentPart(type: "text", text: content),
                ContentPart(type: "image_url", image_url: image_url)
            ])
        } else {
            self.content = .string(content)
        }
        self.image_url = image_url
    }
    
    // Custom decoder to handle missing fields in streaming responses
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        
        // Content can be missing in some streaming delta chunks
        if container.contains(.content) {
            // Try to decode as ContentType
            if let contentString = try? container.decode(String.self, forKey: .content) {
                content = .string(contentString)
            } else if let contentArray = try? container.decode([ContentPart].self, forKey: .content) {
                content = .array(contentArray)
            } else {
                content = nil
            }
        } else {
            content = nil
        }
        
        image_url = try container.decodeIfPresent(ImageURL.self, forKey: .image_url)
    }
    
    // Custom encoder to handle optional fields
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Role and content should always be present when encoding (for requests)
        if let role = role {
            try container.encode(role, forKey: .role)
        }
        
        // Encode content if present - manually encode based on ContentType
        if let content = content {
            switch content {
            case .string(let string):
                try container.encode(string, forKey: .content)
            case .array(let array):
                try container.encode(array, forKey: .content)
            }
        }
        
        try container.encodeIfPresent(image_url, forKey: .image_url)
    }
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double?
    let max_tokens: Int?
    let stream: Bool
}

struct ChatCompletionResponse: Codable {
    let id: String?
    let object: String?
    let created: Int?
    let model: String?
    let choices: [Choice]?
    let usage: Usage?
}

struct Choice: Codable {
    let index: Int?
    let message: ChatMessage?
    let delta: ChatMessage?
    let finish_reason: String?
}

struct Usage: Codable {
    let prompt_tokens: Int?
    let completion_tokens: Int?
    let total_tokens: Int?
}

// MARK: - Model Provider Protocol

/// Unified protocol that all model providers must implement.
/// This abstraction allows Molten to support multiple backends
/// (Ollama, Swama, Apple Foundation Models) through a single interface.
///
/// All providers must:
/// - Check if they're reachable/available
/// - List available models
/// - Stream chat completions
///
/// Implementations:
/// - `OllamaService`: Ollama API client
/// - `SwamaService`: Swama (MLX) API client
/// - `AppleFoundationService`: Apple Foundation Models interface
protocol ModelProviderProtocol: Sendable {
    /// Check if the provider service is reachable/available
    func reachable() async -> Bool
    
    /// Get list of available models from this provider
    func getModels() async throws -> [LanguageModel]
    
    /// Stream chat completions from the provider
    /// - Parameters:
    ///   - model: The model name to use
    ///   - messages: Array of chat messages
    ///   - temperature: Optional temperature parameter
    ///   - maxTokens: Optional max tokens parameter
    /// - Returns: Async stream of ChatCompletionResponse
    func chatStream(
        model: String,
        messages: [ChatMessage],
        temperature: Double?,
        maxTokens: Int?
    ) -> AsyncThrowingStream<ChatCompletionResponse, Error>
}

/// Helper to get provider prefix for UI display
extension ModelProvider {
    var displayPrefix: String {
        switch self {
        case .swama: return "S:"
        case .ollama: return "O:"
        case .appleFoundation: return "A:"
        }
    }
    
    var displayName: String {
        switch self {
        case .swama: return "Swama"
        case .ollama: return "Ollama"
        case .appleFoundation: return "Apple Foundation"
        }
    }
}


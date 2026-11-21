//
//  EmbeddingService.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-E stub. M1/M3: MLXEmbedders at the pinned revision; mean pooling, L2
/// normalization; query/passage prefixes; fp16 storage, fp32 compute.
actor EmbeddingService {
    private(set) var isReady: Bool = false

    func ensureModel(progress: @Sendable (Double) -> Void) async throws {
        throw KnowledgeError.notImplemented("EmbeddingService.ensureModel — M1/M3")
    }
    func embed(passages: [String]) async throws -> [[Float]] {
        throw KnowledgeError.notImplemented("EmbeddingService.embed(passages:) — M3")
    }
    func embed(query: String) async throws -> [Float] {
        throw KnowledgeError.notImplemented("EmbeddingService.embed(query:) — M3")
    }
}

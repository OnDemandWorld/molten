//
//  EmbeddingService.swift
//  Molten
//
//  Molten 2.0 — M1 spike implementation (K-E1/K-E3/K-E5/K-E6).
//  MLXEmbedders at the pinned revision; mean pooling, L2 normalization;
//  query/passage prefixes; e5 tokenizer for token counts.
//

import Foundation
import MLX
import MLXEmbedders
import MLXLMCommon
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge.embed")

actor EmbeddingService {
    static let shared = EmbeddingService()

    private(set) var isReady: Bool = false
    private var container: EmbedderModelContainer?
    let profile = EmbeddingProfile.e5sV1

    /// K-E3: download once at the pinned revision, then load. Until ready,
    /// callers fall back to keyword-only search (K-R2).
    func ensureModel(progress: @Sendable @escaping (Double) -> Void) async throws {
        if isReady { return }
        let configuration = ModelConfiguration(
            id: profile.modelID, revision: profile.modelRevision)
        let loaded = try await EmbedderModelFactory.shared.loadContainer(
            from: HFSnapshotDownloader(),
            using: TransformersTokenizerLoader(),
            configuration: configuration
        ) { p in
            progress(p.fractionCompleted)
        }
        container = loaded
        isReady = true
        logger.info("Embedding model ready: \(self.profile.modelID, privacy: .public)@\(self.profile.modelRevision, privacy: .public)")
    }

    /// K-E1: "passage: " prefix, mean pooling, unit-length vectors.
    func embed(passages: [String]) async throws -> [[Float]] {
        try await embed(texts: passages, prefix: profile.passagePrefix)
    }

    /// K-E6: chunk token counts use the e5 tokenizer, not the chat model's.
    /// Falls back to the character estimate until the model is ready.
    func countTokens(_ text: String) async -> Int {
        guard let container else { return TokenEstimator.estimate(text) }
        return await container.perform { context in
            context.tokenizer.encode(text: text, addSpecialTokens: false).count
        }
    }

    /// K-E1: "query: " prefix. Each device embeds only its own questions (K-E5).
    func embed(query: String) async throws -> [Float] {
        let result = try await embed(texts: [query], prefix: profile.queryPrefix)
        guard let vector = result.first else {
            throw KnowledgeError.notImplemented("Empty embedding result")
        }
        return vector
    }

    private func embed(texts: [String], prefix: String) async throws -> [[Float]] {
        guard let container else { throw KnowledgeError.modelNotReady }
        guard !texts.isEmpty else { return [] }
        let maxTokens = profile.maxTokens
        return await container.perform { context in
            let model = context.model
            let tokenizer = context.tokenizer
            let pooling = context.pooling
            let inputs = texts.map { text -> [Int] in
                var tokens = tokenizer.encode(text: prefix + text, addSpecialTokens: true)
                if tokens.count > maxTokens { tokens = Array(tokens.prefix(maxTokens)) }
                return tokens
            }
            let maxLength = inputs.reduce(into: 16) { acc, elem in acc = max(acc, elem.count) }
            let padId = tokenizer.eosTokenId ?? 0
            let padded = stacked(inputs.map { elem in
                MLXArray(elem + Array(repeating: padId, count: maxLength - elem.count))
            })
            // Mask by position, not token value: padId is the eos token, so a
            // value comparison would also hide each sequence's real trailing
            // [SEP]/EOS from attention and pooling.
            let mask = stacked(inputs.map { elem in
                MLXArray((0..<maxLength).map { $0 < elem.count ? 1 : 0 })
            })
            let tokenTypes = MLXArray.zeros(like: padded)
            let output = model(padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask)
            // Mean pooling must exclude padding positions too.
            let pooled = pooling(output, mask: mask, normalize: true, applyLayerNorm: true)
            pooled.eval()
            return pooled.map { $0.asArray(Float.self) }
        }
    }
}

//
//  Retriever.swift
//  Molten
//
//  Molten 2.0 — M3, K-R2/K-R3/K-R7. Hybrid search when the embedding model
//  is ready; keyword-only otherwise (labelled in the UI). Retrieval is
//  independent of which chat model answers.
//

import Foundation

enum SearchMode: Sendable {
    case hybrid
    case keywordOnly // K-R2: "Keyword search — semantic search after setup"
}

struct RetrievalResult: Sendable {
    let passages: [Passage]
    let mode: SearchMode
}

actor Retriever {
    static let shared = Retriever()

    private let store: KnowledgeStore
    private let embeddings: EmbeddingService

    init(store: KnowledgeStore = .shared, embeddings: EmbeddingService = .shared) {
        self.store = store
        self.embeddings = embeddings
    }

    func retrieve(query: String, base: BaseID, limit: Int = 8) async -> RetrievalResult {
        var vector: [Float]?
        if await embeddings.isReady {
            vector = try? await embeddings.embed(query: query)
        }
        let passages = await store.search(query, queryVector: vector, base: base, limit: limit)
        return RetrievalResult(passages: passages, mode: vector == nil ? .keywordOnly : .hybrid)
    }

    /// K-R6: plain passage search, no LLM.
    func passages(matching query: String, base: BaseID, limit: Int = 20) async -> [Passage] {
        await store.passages(matching: query, base: base, limit: limit)
    }
}

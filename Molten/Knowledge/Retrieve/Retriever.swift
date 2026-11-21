//
//  Retriever.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-R2/K-R3 stub. M3: FTS5 BM25 top-20 + vDSP cosine top-20, merged with
/// reciprocal rank fusion (k = 60); keyword-only fallback without a model.
actor Retriever {
    func retrieve(query: String, base: BaseID, limit: Int) async -> [Passage] {
        [] // M3
    }
}

//
//  EmbeddingProfile.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-E1 / §7.2. One profile on every device; vectors never mix across
/// profiles or revisions (K-E2, A6).
struct EmbeddingProfile: Codable, Sendable, Hashable {
    let id: String               // "e5s-v1"
    let modelID: String          // "intfloat/multilingual-e5-small"
    let modelRevision: String    // pinned commit hash (set in M1 spike)
    let dims: Int                // 384
    let pooling: String          // "mean"
    let normalize: Bool          // true
    let queryPrefix: String      // "query: "
    let passagePrefix: String    // "passage: "
    let maxTokens: Int           // 512

    /// K-E1 profile. Revision pinned to the Hugging Face commit hash verified
    /// during the M1 spike (2026-11-13). Never change without a K-E4 migration.
    static let e5sV1 = EmbeddingProfile(
        id: "e5s-v1",
        modelID: "intfloat/multilingual-e5-small",
        modelRevision: "614241f622f53c4eeff9890bdc4f31cfecc418b3",
        dims: 384,
        pooling: "mean",
        normalize: true,
        queryPrefix: "query: ",
        passagePrefix: "passage: ",
        maxTokens: 512
    )
}

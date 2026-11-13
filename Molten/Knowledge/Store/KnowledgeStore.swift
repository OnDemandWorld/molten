//
//  KnowledgeStore.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-D4: local SQLite (FTS5 + vector table) built from .mkt/.mkv files, with
/// a local file cache so search never depends on iCloud download state.
typealias BaseID = String

struct Passage: Sendable, Identifiable {
    let id: String
    let text: String
    let sourceName: String
    let page: Int?
    let charStart: Int
    let charEnd: Int
    var score: Double
}

enum KnowledgeError: Error {
    case notImplemented(String)
    case modelNotReady
}

/// §7.2 stub. M3 implements ingest + hybrid search (K-R2/K-R3).
actor KnowledgeStore {
    func ingest(mkt: URL) async throws {
        throw KnowledgeError.notImplemented("KnowledgeStore.ingest(mkt:) — M3")
    }
    func ingest(mkv: URL) async throws {
        throw KnowledgeError.notImplemented("KnowledgeStore.ingest(mkv:) — M3")
    }
    func search(_ query: String, queryVector: [Float]?, base: BaseID, limit: Int) async -> [Passage] {
        [] // M3
    }
}

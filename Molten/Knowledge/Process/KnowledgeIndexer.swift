//
//  KnowledgeIndexer.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-P1: stages are claimed separately; outputs are content-addressed.
enum Stage: String, Codable, Sendable { case extract, embed }

/// K-P7 stub. M3 (local) / M4 (iCloud) implement the pipeline:
/// hash → check outputs → claim → download → coordinate → extract → chunk →
/// embed → coordinated write → release.
actor KnowledgeIndexer {
    func scan(base: URL) async { /* M3/M4 */ }
    func process(hash: String, source: URL, stages: Set<Stage>) async throws { /* M3/M4 */ }
}

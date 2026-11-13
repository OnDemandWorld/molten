//
//  Manifest.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// §7.3 manifest.json. First device to find none creates it; later changes
/// are coordinated writes (M4). K-E4 migration fields are reserved now.
struct Manifest: Codable, Sendable {
    var schema: Int
    var activeProfile: String
    var migratingProfile: String?
    var profiles: [String: EmbeddingProfile]
    var chunkerVersion: Int
    var createdBy: String
    var updatedAt: String
}

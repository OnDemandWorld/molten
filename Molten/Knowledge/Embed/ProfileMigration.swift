//
//  ProfileMigration.swift
//  Molten
//
//  Molten 2.0 — K-E4 (M7/A12). Changing the embedding model re-embeds from
//  existing .mkt files ONLY — no re-extraction, no OCR. The old profile keeps
//  serving searches until the new one covers 100% of documents; then the
//  active profile switches and old vectors are deleted after 7 days.
//

import Foundation

struct MigrationPlan: Sendable {
    let needsEmbedding: [String]   // hashes with .mkt but no new-profile .mkv
    let alreadyCovered: [String]
    var coverage: Double {
        let total = needsEmbedding.count + alreadyCovered.count
        return total == 0 ? 1 : Double(alreadyCovered.count) / Double(total)
    }
}

enum ProfileMigration {
    /// Pure planning (unit-tested): which documents need re-embedding.
    static func plan(mktHashes: Set<String>, newProfileMKVHashes: Set<String>) -> MigrationPlan {
        let covered = mktHashes.intersection(newProfileMKVHashes)
        let needs = mktHashes.subtracting(newProfileMKVHashes)
        return MigrationPlan(needsEmbedding: Array(needs).sorted(), alreadyCovered: Array(covered).sorted())
    }

    /// Manifest transition: mark the new profile as migrating (K-E4).
    static func beginMigration(manifest: inout Manifest, newProfile: EmbeddingProfile) {
        manifest.profiles[newProfile.id] = newProfile
        manifest.migratingProfile = newProfile.id
        manifest.updatedAt = ISO8601DateFormatter().string(from: Date())
    }

    /// Switch active only at 100% coverage; old profile kept for the grace
    /// period, then removed by cleanup.
    static func completeMigration(manifest: inout Manifest, coverage: Double) -> Bool {
        guard coverage >= 1.0, let migrating = manifest.migratingProfile else { return false }
        manifest.activeProfile = migrating
        manifest.migratingProfile = nil
        manifest.updatedAt = ISO8601DateFormatter().string(from: Date())
        return true
    }

    /// Re-embed one document from its .mkt (no extraction/OCR — A12).
    static func reembed(
        hash: String,
        profile: EmbeddingProfile,
        textDirectory: URL,
        vectorsDirectory: URL,
        embeddings: EmbeddingService
    ) async throws {
        let mktURL = textDirectory.appendingPathComponent("\(hash).mkt")
        let mkvURL = vectorsDirectory.appendingPathComponent("\(hash).mkv")
        if FileManager.default.fileExists(atPath: mkvURL.path) { return }
        let document = try MKTCodec.decode(Data(contentsOf: mktURL))
        let vectors = try await embeddings.embed(passages: document.chunks.map(\.text))
        let header = MKVHeader(
            schema: 1,
            sourceHash: hash,
            profileID: profile.id,
            modelRevision: profile.modelRevision,
            dims: profile.dims,
            count: vectors.count,
            chunkerVersion: document.chunkerVersion,
            encryption: nil,
            createdBy: DeviceIdentity.id,
            createdAt: ISO8601DateFormatter().string(from: Date()))
        try CoordinatedIO.writeOnce(MKVCodec.encode(header: header, vectors: vectors), to: mkvURL)
    }
}

//
//  Manifest.swift
//  Molten
//
//  Molten 2.0 — M4, §7.3/K-E2/K-E4. manifest.json names the active embedding
//  profile; the first device to find none creates it; later changes are
//  coordinated writes. Vectors from different profiles/revisions never mix.
//

import Foundation

struct Manifest: Codable, Sendable {
    var schema: Int
    var activeProfile: String
    var migratingProfile: String?
    var profiles: [String: EmbeddingProfile]
    var chunkerVersion: Int
    var createdBy: String
    var updatedAt: String

    static func initial(deviceID: String) -> Manifest {
        Manifest(
            schema: 1,
            activeProfile: EmbeddingProfile.e5sV1.id,
            migratingProfile: nil,
            profiles: [EmbeddingProfile.e5sV1.id: EmbeddingProfile.e5sV1],
            chunkerVersion: Chunker.chunkerVersion,
            createdBy: deviceID,
            updatedAt: ISO8601DateFormatter().string(from: Date()))
    }
}

enum ManifestStore {
    static var url: URL {
        KnowledgeContainer.indexRoot().appendingPathComponent("manifest.json")
    }

    /// Load the manifest; create it when absent (first device wins —
    /// duplicate creation is harmless because content is deterministic).
    static func loadOrCreate() -> Manifest {
        if let data = CoordinatedIO.read(url),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
            return manifest
        }
        let manifest = Manifest.initial(deviceID: DeviceIdentity.id)
        if let data = try? JSONEncoder().encode(manifest) {
            try? CoordinatedIO.writeOnce(data, to: url)
        }
        return manifest
    }

    /// K-E2: a device uses only vectors whose profile AND revision match.
    static func accepts(header: MKVHeader, manifest: Manifest) -> Bool {
        guard let profile = manifest.profiles[header.profileID] else { return false }
        return header.profileID == manifest.activeProfile
            && header.modelRevision == profile.modelRevision
            && header.dims == profile.dims
    }
}

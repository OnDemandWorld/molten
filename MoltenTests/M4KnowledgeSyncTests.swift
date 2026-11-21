//
//  M4KnowledgeSyncTests.swift
//  MoltenTests
//
//  Molten 2.0 — M4: manifest/profile gating (A6), coordinated write-once
//  (K-D3), placeholder filtering (§7.4), mapping stability (A5), migration
//  preserves content-hash names (A14). Two-device acceptance (A2/A13) is a
//  manual owner test (DEVIATIONS.md).
//

import Foundation
import Testing
@testable import Molten

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("m4-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("M4 — Manifest + profile gating (K-E2/A6)")
struct ManifestTests {
    @Test func initialManifestNamesE5Profile() {
        let manifest = Manifest.initial(deviceID: "test")
        #expect(manifest.activeProfile == "e5s-v1")
        #expect(manifest.profiles["e5s-v1"]?.dims == 384)
        #expect(manifest.migratingProfile == nil)
    }

    @Test func acceptsOnlyMatchingProfileAndRevision() {
        let manifest = Manifest.initial(deviceID: "test")
        let profile = EmbeddingProfile.e5sV1
        func header(profileID: String, revision: String, dims: Int = 384) -> MKVHeader {
            MKVHeader(schema: 1, sourceHash: "h", profileID: profileID,
                      modelRevision: revision, dims: dims, count: 1,
                      chunkerVersion: 1, encryption: nil, createdBy: "t", createdAt: "t")
        }
        #expect(ManifestStore.accepts(header: header(profileID: profile.id, revision: profile.modelRevision), manifest: manifest))
        // Different revision → rejected (A6).
        #expect(!ManifestStore.accepts(header: header(profileID: profile.id, revision: "other"), manifest: manifest))
        // Unknown profile → rejected.
        #expect(!ManifestStore.accepts(header: header(profileID: "other", revision: profile.modelRevision), manifest: manifest))
        // Wrong dims → rejected.
        #expect(!ManifestStore.accepts(header: header(profileID: profile.id, revision: profile.modelRevision, dims: 256), manifest: manifest))
    }

    @Test func manifestJSONRoundTrip() throws {
        let manifest = Manifest.initial(deviceID: "test")
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(Manifest.self, from: data)
        #expect(decoded.activeProfile == manifest.activeProfile)
        #expect(decoded.profiles.count == 1)
    }
}

@Suite("M4 — Coordinated IO (§7.4/K-D3)")
struct CoordinatedIOTests {
    @Test func writeOnceSkipsExisting() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("out.mkt")
        try CoordinatedIO.writeOnce(Data("first".utf8), to: file)
        try CoordinatedIO.writeOnce(Data("second".utf8), to: file)
        #expect(try Data(contentsOf: file) == Data("first".utf8))
    }

    @Test func readWriteRoundTrip() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("data.bin")
        let payload = Data((0..<10000).map { UInt8($0 % 256) })
        try CoordinatedIO.writeOnce(payload, to: file)
        #expect(CoordinatedIO.read(file) == payload)
    }

    @Test func placeholderDetection() {
        #expect(CoordinatedIO.isPlaceholderOrConflict(URL(fileURLWithPath: "/x/.doc.pdf.icloud")))
        #expect(CoordinatedIO.isPlaceholderOrConflict(URL(fileURLWithPath: "/x/doc (conflict 2026-01-01).pdf")))
        #expect(!CoordinatedIO.isPlaceholderOrConflict(URL(fileURLWithPath: "/x/doc.pdf")))
    }

    @Test func movePreservesContentHashName() throws {
        // A14: migration moves files without renaming — hash names intact.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hash = String(repeating: "cd", count: 32)
        let source = dir.appendingPathComponent("local/text/\(hash).mkt")
        let dest = dir.appendingPathComponent("icloud/text/\(hash).mkt")
        try CoordinatedIO.writeOnce(Data("content".utf8), to: source)
        try CoordinatedIO.move(from: source, to: dest)
        #expect(FileManager.default.fileExists(atPath: dest.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(dest.lastPathComponent == "\(hash).mkt")
    }

    @Test func sha256StableAcrossRenames() throws {
        // A5: rename/move never changes the hash → no reprocessing.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("original.pdf")
        let b = dir.appendingPathComponent("renamed.pdf")
        try Data("same bytes".utf8).write(to: a)
        try FileManager.default.copyItem(at: a, to: b)
        #expect(try KnowledgeIndexer.sha256(of: a) == KnowledgeIndexer.sha256(of: b))
    }
}

@Suite("M4 — File mapping (K-D5)", .serialized)
struct FileMappingTests {
    @Test func updateAndReferencedHashes() async {
        let mapping = FileMapping()
        await mapping.update(path: "/docs/base/a.pdf", entry: FileMapEntry(hash: "h1", base: "base", name: "a.pdf", mtime: 1))
        await mapping.update(path: "/docs/base/b.pdf", entry: FileMapEntry(hash: "h2", base: "base", name: "b.pdf", mtime: 2))
        #expect(await mapping.referencedHashes() == Set(["h1", "h2"]))
        await mapping.remove(path: "/docs/base/a.pdf")
        #expect(await mapping.referencedHashes() == Set(["h2"]))
        #expect(await mapping.entry(forPath: "/docs/base/b.pdf")?.hash == "h2")
    }
}

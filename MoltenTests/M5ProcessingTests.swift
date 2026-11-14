//
//  M5ProcessingTests.swift
//  MoltenTests
//
//  Molten 2.0 — M5 exit criteria: claim-expiry and takeover tests (K-P2),
//  failure markers (K-P11), heartbeat freshness and device roles (K-P3),
//  stage policy (K-P4). Two-device manual script in DEVIATIONS.md.
//

import Foundation
import Testing
@testable import Molten

private func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("m5-tests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("M5 — Claims (K-P2/K-P11)", .serialized)
struct ClaimTests {
    @Test func claimBlocksOtherDeviceUntilExpiry() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date()
        let clock = LockedClock(t0)
        let a = ClaimStore(directory: dir, deviceID: "device-A", now: { clock.now })
        let b = ClaimStore(directory: dir, deviceID: "device-B", now: { clock.now })

        #expect(await a.tryClaim(hash: "h1", stage: .extract))
        // Valid lease blocks the other device.
        #expect(await !b.tryClaim(hash: "h1", stage: .extract))
        // Expired lease may be taken over.
        clock.now = t0.addingTimeInterval(ClaimStore.leaseDuration + 1)
        #expect(await b.tryClaim(hash: "h1", stage: .extract))
    }

    @Test func renewExtendsLease() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t0 = Date()
        let clock = LockedClock(t0)
        let a = ClaimStore(directory: dir, deviceID: "A", now: { clock.now })
        let b = ClaimStore(directory: dir, deviceID: "B", now: { clock.now })
        #expect(await a.tryClaim(hash: "h", stage: .embed))
        clock.now = t0.addingTimeInterval(ClaimStore.leaseDuration - 10)
        await a.renew(hash: "h", stage: .embed)
        clock.now = t0.addingTimeInterval(ClaimStore.leaseDuration + 100)
        // Renewed lease still valid past the original expiry.
        #expect(await !b.tryClaim(hash: "h", stage: .embed))
    }

    @Test func releaseFreesClaim() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = ClaimStore(directory: dir, deviceID: "A")
        let b = ClaimStore(directory: dir, deviceID: "B")
        #expect(await a.tryClaim(hash: "h", stage: .extract))
        await a.release(hash: "h", stage: .extract, failed: nil)
        #expect(await b.tryClaim(hash: "h", stage: .extract))
    }

    @Test func threeFailuresWriteFailedMarker() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = ClaimStore(directory: dir, deviceID: "A")
        let b = ClaimStore(directory: dir, deviceID: "B")
        for _ in 0..<3 {
            #expect(await a.tryClaim(hash: "h", stage: .extract))
            await a.release(hash: "h", stage: .extract, failed: "boom")
        }
        #expect(await a.hasFailed(hash: "h", stage: .extract))
        #expect(await a.failureReason(hash: "h", stage: .extract) == "boom")
        // Other devices do not retry automatically (K-P11).
        #expect(await !b.tryClaim(hash: "h", stage: .extract))
        // Manual retry clears the marker.
        await a.retry(hash: "h", stage: .extract)
        #expect(await b.tryClaim(hash: "h", stage: .extract))
    }

    @Test func stagesAreIndependent() async {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = ClaimStore(directory: dir, deviceID: "A")
        let b = ClaimStore(directory: dir, deviceID: "B")
        #expect(await a.tryClaim(hash: "h", stage: .extract))
        // Embed is a separate claim — another device may embed.
        #expect(await b.tryClaim(hash: "h", stage: .embed))
    }
}

private final class LockedClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date) { value = date }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

@Suite("M5 — Device roles (K-P3/K-P4)")
struct DeviceRoleTests {
    private func heartbeat(platform: String, ageHours: Double) -> Heartbeat {
        Heartbeat(platform: platform, model: "Test",
                  lastSeen: Date().addingTimeInterval(-ageHours * 3600),
                  canEmbed: true, appVersion: "2.0")
    }

    @Test func macFreshnessWindow() {
        let now = Date()
        let fresh = ["m": heartbeat(platform: "macOS", ageHours: 23)]
        let stale = ["m": heartbeat(platform: "macOS", ageHours: 25)]
        #expect(DeviceRoles.macIsActive(fresh, now: now))
        #expect(!DeviceRoles.macIsActive(stale, now: now))
        #expect(!DeviceRoles.macIsActive([:], now: now))
    }

    @Test func deferRequiresOptInAndFreshMac() {
        let now = Date()
        let devices = ["m": heartbeat(platform: "macOS", ageHours: 1)]
        #expect(DeviceRoles.shouldDeferToMac(devices: devices, letMacDoIt: true, now: now) == !isMac)
        #expect(!DeviceRoles.shouldDeferToMac(devices: devices, letMacDoIt: false, now: now))
        #expect(!DeviceRoles.shouldDeferToMac(devices: [:], letMacDoIt: true, now: now))
    }

    @Test func stagePolicy() {
        #if os(macOS)
        // macOS always runs both stages.
        #expect(DeviceRoles.allowedStages(policy: .bothWhileCharging, isCharging: false) == Set([.extract, .embed]))
        #else
        // K-P4: extract-only on battery, both while charging, always-both opt-in.
        #expect(DeviceRoles.allowedStages(policy: .bothWhileCharging, isCharging: false) == Set([.extract]))
        #expect(DeviceRoles.allowedStages(policy: .bothWhileCharging, isCharging: true) == Set([.extract, .embed]))
        #expect(DeviceRoles.allowedStages(policy: .alwaysBoth, isCharging: false) == Set([.extract, .embed]))
        #endif
    }

    private var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}

@Suite("M5 — Resume durability (A3/A5)", .serialized)
struct ResumeDurabilityTests {
    @Test func reprocessingNeverRewritesCompletedOutputs() async throws {
        // A3's durability guarantee: work is saved per file/per stage, so a
        // killed-and-resumed run skips completed stages instead of redoing
        // them. Simulate: write outputs, then verify writeOnce + hash-skip
        // leave them byte-identical on the second pass.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("doc.txt")
        try "durable content".write(to: source, atomically: true, encoding: .utf8)
        let hash = try KnowledgeIndexer.sha256(of: source)
        let output = dir.appendingPathComponent("\(hash).mkt")
        let document = MKTDocument(
            schema: 1, sourceHash: hash, mime: "text/plain", extractorVersion: 1,
            ocrUsed: false, chunkerVersion: 1, pages: [], chunks: [],
            encryption: nil, createdBy: "t", createdAt: "t")
        let bytes = try MKTCodec.encode(document)
        try CoordinatedIO.writeOnce(bytes, to: output)
        let mtime1 = try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date

        // "Resume": a fresh pass must skip the completed output entirely.
        try CoordinatedIO.writeOnce(Data("different".utf8), to: output)
        let mtime2 = try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date
        #expect(try Data(contentsOf: output) == bytes)
        #expect(mtime1 == mtime2)
        // Same content under a new name → same hash → same output path (A5).
        let renamed = dir.appendingPathComponent("renamed.txt")
        try FileManager.default.copyItem(at: source, to: renamed)
        #expect(try KnowledgeIndexer.sha256(of: renamed) == hash)
    }
}

@Suite("M5 — Heartbeats (K-P5)", .serialized)
struct HeartbeatTests {
    @Test func beatWritesDecodableHeartbeat() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = HeartbeatService(directory: dir, deviceID: "test-device")
        await service.beat(canEmbed: true)
        let devices = await service.devices()
        let beat = try #require(devices["test-device"])
        #expect(beat.canEmbed)
        #expect(beat.appVersion.count > 0)
        #expect(Date().timeIntervalSince(beat.lastSeen) < 60)
    }
}

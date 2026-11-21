//
//  ClaimStore.swift
//  Molten
//
//  Molten 2.0 — M5, K-P2/K-P11. Per-document, per-stage processing claims:
//  JSON {deviceID, stage, leaseExpiresAt}; 10-minute leases renewed every
//  60s; expired claims may be taken over; claims deleted on finish/failure.
//  After 3 failed attempts for the same hash+stage a .failed marker is
//  written and other devices do not retry automatically.
//

import Foundation

struct Claim: Codable, Sendable, Equatable {
    let deviceID: String
    let stage: String
    let leaseExpiresAt: Date
}

actor ClaimStore {
    static let leaseDuration: TimeInterval = 600   // 10 minutes
    static let renewInterval: TimeInterval = 60    // 60 seconds
    static let maxAttempts = 3

    private let directory: URL
    private let deviceID: String
    private let now: @Sendable () -> Date
    private var attempts: [String: Int] = [:]

    init(directory: URL? = nil, deviceID: String? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory ?? KnowledgeContainer.indexRoot()
            .appendingPathComponent("claims", isDirectory: true)
        self.deviceID = deviceID ?? DeviceIdentity.id
        self.now = now
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func claimURL(_ hash: String, _ stage: Stage) -> URL {
        directory.appendingPathComponent("\(hash).\(stage.rawValue).claim")
    }

    private func failedURL(_ hash: String, _ stage: Stage) -> URL {
        directory.appendingPathComponent("\(hash).\(stage.rawValue).failed")
    }

    /// K-P11: a failed marker blocks automatic retries on every device.
    func hasFailed(hash: String, stage: Stage) -> Bool {
        FileManager.default.fileExists(atPath: failedURL(hash, stage).path)
    }

    func failureReason(hash: String, stage: Stage) -> String? {
        guard let data = try? Data(contentsOf: failedURL(hash, stage)) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Claim a stage. Skips files with a valid claim from another device;
    /// takes over expired ones (K-P2).
    func tryClaim(hash: String, stage: Stage) -> Bool {
        if hasFailed(hash: hash, stage: stage) { return false }
        let url = claimURL(hash, stage)
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode(Claim.self, from: data) {
            if existing.deviceID != deviceID && existing.leaseExpiresAt > now() {
                return false // another device holds a valid lease
            }
        }
        let claim = Claim(deviceID: deviceID, stage: stage.rawValue,
                          leaseExpiresAt: now().addingTimeInterval(Self.leaseDuration))
        guard let data = try? JSONEncoder().encode(claim) else { return false }
        do {
            try CoordinatedIO.writeOnce(data, to: url)
            // writeOnce skips existing files — overwrite our own takeover.
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Renew our lease (called every 60s while processing).
    func renew(hash: String, stage: Stage) {
        let url = claimURL(hash, stage)
        guard let data = try? Data(contentsOf: url),
              var claim = try? JSONDecoder().decode(Claim.self, from: data),
              claim.deviceID == deviceID else { return }
        claim = Claim(deviceID: deviceID, stage: stage.rawValue,
                      leaseExpiresAt: now().addingTimeInterval(Self.leaseDuration))
        if let updated = try? JSONEncoder().encode(claim) {
            try? updated.write(to: url, options: .atomic)
        }
    }

    /// Release on finish; on failure count attempts and mark .failed at 3.
    func release(hash: String, stage: Stage, failed: String?) {
        let url = claimURL(hash, stage)
        try? FileManager.default.removeItem(at: url)
        guard let reason = failed else {
            attempts["\(hash).\(stage.rawValue)"] = 0
            return
        }
        let key = "\(hash).\(stage.rawValue)"
        attempts[key, default: 0] += 1
        if attempts[key, default: 0] >= Self.maxAttempts {
            try? reason.data(using: .utf8)?.write(to: failedURL(hash, stage), options: .atomic)
        }
    }

    /// K-P11 UI: manual retry clears the failed marker and attempt count.
    func retry(hash: String, stage: Stage) {
        try? FileManager.default.removeItem(at: failedURL(hash, stage))
        attempts["\(hash).\(stage.rawValue)"] = 0
    }
}

//
//  HeartbeatService.swift
//  Molten
//
//  Molten 2.0 — M5, K-P5. Each device writes devices/<deviceID>.json every
//  15 minutes while active: {platform, model, lastSeen, canEmbed, appVersion}.
//  deviceID is a random UUID in UserDefaults — no hardware identifiers.
//

import Foundation
#if os(iOS)
import UIKit
#endif

struct Heartbeat: Codable, Sendable, Equatable {
    let platform: String
    let model: String
    let lastSeen: Date
    let canEmbed: Bool
    let appVersion: String
}

actor HeartbeatService {
    static let shared = HeartbeatService()
    static let interval: TimeInterval = 900 // 15 minutes

    private let directory: URL
    private let deviceID: String
    private var task: Task<Void, Never>?

    init(directory: URL? = nil, deviceID: String? = nil) {
        self.directory = directory ?? KnowledgeContainer.indexRoot()
            .appendingPathComponent("devices", isDirectory: true)
        self.deviceID = deviceID ?? DeviceIdentity.id
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func start(canEmbed: @escaping @Sendable () async -> Bool) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.beat(canEmbed: await canEmbed())
                try? await Task.sleep(nanoseconds: UInt64(Self.interval * 1_000_000_000))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func beat(canEmbed: Bool) {
        let heartbeat = Heartbeat(
            platform: EarlySupporterDetector.currentPlatform.rawValue,
            model: DeviceModel.name,
            lastSeen: Date(),
            canEmbed: canEmbed,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")
        guard let data = try? JSONEncoder().encode(heartbeat) else { return }
        let url = directory.appendingPathComponent("\(deviceID).json")
        try? data.write(to: url, options: .atomic)
    }

    /// All known device heartbeats (for role decisions, K-P3).
    func devices() -> [String: Heartbeat] {
        var result: [String: Heartbeat] = [:]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return result }
        for file in files where file.pathExtension == "json" {
            if let data = try? Data(contentsOf: file),
               let heartbeat = try? JSONDecoder().decode(Heartbeat.self, from: data) {
                result[file.deletingPathExtension().lastPathComponent] = heartbeat
            }
        }
        return result
    }
}

enum DeviceModel {
    static var name: String {
        #if os(macOS)
        return "Mac"
        #else
        return UIDevice.current.model
        #endif
    }
}

// MARK: - Device roles (K-P3/K-P4)

enum ProcessingPolicy: String, Sendable {
    case bothWhileCharging // default: both stages charging, extract-only battery
    case alwaysBoth
}

enum DeviceRoles {
    static let macFreshness: TimeInterval = 24 * 3600

    /// K-P3: a Mac with Molten running (heartbeat < 24h) does the heavy work.
    static func macIsActive(_ devices: [String: Heartbeat], now: Date = Date()) -> Bool {
        devices.values.contains {
            $0.platform == "macOS" && now.timeIntervalSince($0.lastSeen) < macFreshness
        }
    }

    /// K-P3: iOS defers to a fresh Mac when "Let my Mac do the heavy lifting"
    /// is on (default). The UI shows "Waiting for Mac" + "Process now".
    static func shouldDeferToMac(devices: [String: Heartbeat], letMacDoIt: Bool, now: Date = Date()) -> Bool {
        #if os(macOS)
        return false
        #else
        return letMacDoIt && macIsActive(devices, now: now)
        #endif
    }

    /// K-P4: iOS stage policy. Extract alone enables keyword search everywhere.
    static func allowedStages(policy: ProcessingPolicy, isCharging: Bool) -> Set<Stage> {
        #if os(macOS)
        return [.extract, .embed]
        #else
        switch policy {
        case .alwaysBoth: return [.extract, .embed]
        case .bothWhileCharging: return isCharging ? [.extract, .embed] : [.extract]
        }
        #endif
    }

    static var policy: ProcessingPolicy {
        ProcessingPolicy(rawValue: UserDefaults.standard.string(forKey: "knowledgeProcessingPolicy") ?? "") ?? .bothWhileCharging
    }

    static var letMacDoIt: Bool {
        UserDefaults.standard.object(forKey: "knowledgeLetMacDoIt") as? Bool ?? true
    }

    static var isCharging: Bool {
        #if os(macOS)
        return true
        #else
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        return device.batteryState == .charging || device.batteryState == .full
        #endif
    }
}

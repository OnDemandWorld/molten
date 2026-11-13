//
//  EarlySupporterDetector.swift
//  Molten
//
//  Molten 2.0 — M1/M2/M3. Everyone who bought Molten 1.x gets Plus forever.
//  AppTransaction.originalAppVersion vs per-platform cutoffs; sandbox and
//  Xcode environments NEVER grant (M3).
//

import Foundation
import StoreKit

struct EarlySupporterDetection: Codable, Sendable, Equatable {
    let originalVersion: String
    let platform: String
    let detectedAt: Date
}

enum EarlySupporterDetector {
    /// M2: macOS reports the original marketing version (CFBundleShortVersionString).
    static let macCutoffMarketingVersion = "2.0"

    /// M2: iOS/iPadOS report the original build number (CFBundleVersion).
    /// OWNER ACTION (DEVIATIONS.md): set from App Store Connect 1.x build
    /// history; every 2.0 build must be numerically greater. nil = fail-closed
    /// (no iOS grants until confirmed).
    static let iosCutoffBuild: Int? = nil

    enum Platform: String, Sendable { case macOS, iOS }
    enum Env: Sendable { case production, sandbox, xcode }

    /// Pure decision logic (M6 unit tests cover the full matrix).
    static func isEarlySupporter(
        platform: Platform,
        originalVersion: String,
        environment: Env,
        iosCutoff: Int?
    ) -> Bool {
        guard environment == .production else { return false } // M3
        switch platform {
        case .macOS:
            return VersionCompare.isBefore(originalVersion, cutoff: macCutoffMarketingVersion) ?? false
        case .iOS:
            guard let cutoff = iosCutoff,
                  let build = Int(originalVersion.trimmingCharacters(in: .whitespacesAndNewlines))
            else { return false }
            return build < cutoff
        }
    }

    #if DEBUG
    /// M3: the only way to simulate Early Supporter status in sandbox/Xcode.
    /// Compiled out of Release builds.
    static var simulateEarlySupporter: Bool {
        get { UserDefaults.standard.bool(forKey: "debugSimulateEarlySupporter") }
        set { UserDefaults.standard.set(newValue, forKey: "debugSimulateEarlySupporter") }
    }
    #endif

    static var currentPlatform: Platform {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }

    /// Live detection via AppTransaction (M1). nil when unverifiable —
    /// callers fall back to the Keychain item (M4/M11).
    static func detect() async -> EarlySupporterDetection? {
        #if DEBUG
        if simulateEarlySupporter {
            return EarlySupporterDetection(
                originalVersion: "1.1",
                platform: currentPlatform.rawValue,
                detectedAt: Date())
        }
        #endif
        do {
            let result = try await AppTransaction.shared
            guard case .verified(let tx) = result else { return nil }
            let env: Env
            if tx.environment == .production {
                env = .production
            } else if tx.environment == .xcode {
                env = .xcode
            } else {
                env = .sandbox
            }
            let version = tx.originalAppVersion
            guard isEarlySupporter(
                platform: currentPlatform,
                originalVersion: version,
                environment: env,
                iosCutoff: iosCutoffBuild
            ) else { return nil }
            return EarlySupporterDetection(
                originalVersion: version,
                platform: currentPlatform.rawValue,
                detectedAt: Date())
        } catch {
            return nil
        }
    }
}

//
//  EarlySupporterDetector.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// M1–M3 stub. M2 implements AppTransaction.originalAppVersion comparison.
enum EarlySupporterDetector {
    /// M2: macOS reports the original marketing version.
    static let macCutoffMarketingVersion = "2.0"
    /// M2: iOS/iPadOS report the original build number. Set from App Store
    /// Connect build history: must exceed every shipped 1.x build (highest
    /// known shipped build: 5, v1.1). See docs/DEVIATIONS.md.
    static let iosCutoffBuild: Int? = nil

    /// M3: sandbox/xcode environments must NEVER grant Early Supporter.
    static func detect() async -> Bool { false }
}

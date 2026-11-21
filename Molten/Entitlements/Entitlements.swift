//
//  Entitlements.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// PRD §5.1 / §7.2. Pro is reserved for a later release (M15).
enum Tier: Int, Comparable, Sendable {
    case free, plus, pro
    static func < (a: Tier, b: Tier) -> Bool { a.rawValue < b.rawValue }
}

enum EntitlementSource: Sendable {
    case none, earlySupporter, subscription, lifetime
}

/// M9: every gated feature declares its tier here; gates call
/// `EntitlementManager.allows(_:)`. No ad-hoc isPlus checks elsewhere.
enum Feature: Sendable {
    case unlimitedKnowledge, iCloudKnowledge, macAssist, ocr
    var requiredTier: Tier {
        switch self {
        default: .plus   // Pro features added later (M15)
        }
    }
}

//
//  EntitlementManager.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// M8 stub. M2 implements: AppTransaction + Transaction.currentEntitlements,
/// Transaction.updates listener, Keychain fallback (M4), @Observable UI model.
actor EntitlementManager {
    static let shared = EntitlementManager()

    private(set) var currentTier: Tier = .free
    private(set) var source: EntitlementSource = .none

    func start() async { /* M2: listen to Transaction.updates from launch */ }
    func refresh() async { /* M2: AppTransaction + currentEntitlements + Keychain */ }
    func allows(_ feature: Feature) -> Bool { currentTier >= feature.requiredTier }
}

//
//  ClaimStore.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-P2 stub. M5: JSON claims {deviceID, stage, leaseExpiresAt}, 10-minute
/// leases renewed every 60s, takeover of expired claims, delete on finish.
actor ClaimStore {
    func tryClaim(hash: String, stage: Stage) async -> Bool { false }
    func renew(hash: String, stage: Stage) async { /* M5 */ }
    func release(hash: String, stage: Stage, failed: String?) async { /* M5 */ }
}

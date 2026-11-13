//
//  M2EntitlementTests.swift
//  MoltenTests
//
//  Molten 2.0 — M6 required test matrix:
//  macOS before/after cutoff; iOS build before/after cutoff; malformed and
//  empty versions; sandbox environment; Early Supporter + subscription;
//  lifetime; Keychain-only grant while offline. Plus StoreKit-testing flows
//  for buy / lapse / lifetime (M2 exit criteria).
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Molten

private final class InMemoryEarlySupporterStore: EarlySupporterStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var detection: EarlySupporterDetection?
    init(_ detection: EarlySupporterDetection? = nil) { self.detection = detection }
    func save(_ d: EarlySupporterDetection) -> Bool {
        lock.lock(); defer { lock.unlock() }
        detection = d
        return true
    }
    func load() -> EarlySupporterDetection? {
        lock.lock(); defer { lock.unlock() }
        return detection
    }
}

private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

/// SKTestSession needs a provisioned (signed) test host; the agent environment
/// cannot provision the iCloud capability (DEVIATIONS.md). Gate the session
/// flows behind a marker so they run in Xcode / provisioned CI, while the
/// pure M6 matrix always runs.
private var storeKitFlowsEnabled: Bool {
    FileManager.default.fileExists(atPath:
        repoRoot.appendingPathComponent("build/session/STOREKIT_FLOWS_ENABLED").path)
}

@Suite("M2 — Version comparison (M2: integer components, never strings)")
struct VersionCompareTests {
    @Test func beforeAndAfter() {
        #expect(VersionCompare.isBefore("1.1", cutoff: "2.0") == true)
        #expect(VersionCompare.isBefore("1.9.9", cutoff: "2.0") == true)
        #expect(VersionCompare.isBefore("2.0", cutoff: "2.0") == false)
        #expect(VersionCompare.isBefore("2.0.1", cutoff: "2.0") == false)
        #expect(VersionCompare.isBefore("2.1", cutoff: "2.0") == false)
    }

    @Test func integerNotLexicographic() {
        #expect(VersionCompare.isBefore("10.0", cutoff: "2.0") == false)
        #expect(VersionCompare.isBefore("2.10", cutoff: "2.9") == false)
    }

    @Test func zeroPadding() {
        #expect(VersionCompare.compare("2", "2.0.0") == .orderedSame)
        #expect(VersionCompare.compare("2.0.1", "2.0") == .orderedDescending)
    }

    @Test func malformedAndEmpty() {
        #expect(VersionCompare.components("") == nil)
        #expect(VersionCompare.components("  ") == nil)
        #expect(VersionCompare.components("1.x") == nil)
        #expect(VersionCompare.components("1..2") == nil)
        #expect(VersionCompare.components(".1") == nil)
        #expect(VersionCompare.components("1.") == nil)
        #expect(VersionCompare.components("-1") == nil)
        #expect(VersionCompare.isBefore("abc", cutoff: "2.0") == nil)
    }
}

@Suite("M2 — Early Supporter decision matrix (M1/M2/M3)")
struct EarlySupporterDecisionTests {
    @Test func macOSCutoff() {
        #expect(EarlySupporterDetector.isEarlySupporter(
            platform: .macOS, originalVersion: "1.1", environment: .production, iosCutoff: nil))
        #expect(EarlySupporterDetector.isEarlySupporter(
            platform: .macOS, originalVersion: "1.0.1", environment: .production, iosCutoff: nil))
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .macOS, originalVersion: "2.0", environment: .production, iosCutoff: nil))
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .macOS, originalVersion: "2.1", environment: .production, iosCutoff: nil))
    }

    @Test func iOSBuildCutoff() {
        #expect(EarlySupporterDetector.isEarlySupporter(
            platform: .iOS, originalVersion: "5", environment: .production, iosCutoff: 6))
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .iOS, originalVersion: "6", environment: .production, iosCutoff: 6))
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .iOS, originalVersion: "7", environment: .production, iosCutoff: 6))
        // Fail-closed until the owner confirms the ASC build history.
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .iOS, originalVersion: "5", environment: .production, iosCutoff: nil))
        // iOS reports a build number, not a marketing version.
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .iOS, originalVersion: "1.1", environment: .production, iosCutoff: 6))
    }

    @Test func sandboxAndXcodeNeverGrant() {
        for env in [EarlySupporterDetector.Env.sandbox, .xcode] {
            #expect(!EarlySupporterDetector.isEarlySupporter(
                platform: .macOS, originalVersion: "1.1", environment: env, iosCutoff: nil))
            #expect(!EarlySupporterDetector.isEarlySupporter(
                platform: .iOS, originalVersion: "5", environment: env, iosCutoff: 6))
        }
    }

    @Test func malformedVersionsNeverGrant() {
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .macOS, originalVersion: "", environment: .production, iosCutoff: nil))
        #expect(!EarlySupporterDetector.isEarlySupporter(
            platform: .macOS, originalVersion: "garbage", environment: .production, iosCutoff: nil))
    }
}

@Suite("M2 — Tier computation (M8)")
struct TierComputationTests {
    @Test func freeByDefault() {
        let (tier, src) = EntitlementManager.computeTier(earlySupporter: false, subscriptionTier: nil, lifetime: false)
        #expect(tier == .free)
        #expect(src == .none)
    }

    @Test func earlySupporterGrantsPlus() {
        let (tier, src) = EntitlementManager.computeTier(earlySupporter: true, subscriptionTier: nil, lifetime: false)
        #expect(tier == .plus)
        #expect(src == .earlySupporter)
    }

    @Test func subscriptionGrantsPlus() {
        let (tier, src) = EntitlementManager.computeTier(earlySupporter: false, subscriptionTier: .plus, lifetime: false)
        #expect(tier == .plus)
        #expect(src == .subscription)
    }

    @Test func lifetimeGrantsPlus() {
        let (tier, src) = EntitlementManager.computeTier(earlySupporter: false, subscriptionTier: nil, lifetime: true)
        #expect(tier == .plus)
        #expect(src == .lifetime)
    }

    @Test func earlySupporterWithSubscriptionKeepsEarlySupporterSource() {
        let (tier, src) = EntitlementManager.computeTier(earlySupporter: true, subscriptionTier: .plus, lifetime: false)
        #expect(tier == .plus)
        #expect(src == .earlySupporter)
    }

    @Test func proSubscriptionWinsOverPlusGrants() {
        let (tier, _) = EntitlementManager.computeTier(earlySupporter: true, subscriptionTier: .pro, lifetime: true)
        #expect(tier == .pro)
    }

    @Test @MainActor func featureGates() async {
        let manager = EntitlementManager(store: InMemoryEarlySupporterStore(), ui: EntitlementUIModel())
        #expect(await !manager.allows(.unlimitedKnowledge))
        #expect(await !manager.allows(.iCloudKnowledge))
        #expect(await !manager.allows(.ocr))
    }
}

@Suite("M2 — Keychain-only offline grant (M4/M11)", .serialized)
@MainActor
struct OfflineGrantTests {
    @Test func keychainItemGrantsPlusWithoutAppTransaction() async {
        // In the test (sandbox) environment AppTransaction never grants, so
        // this exercises the offline Keychain fallback path.
        let detection = EarlySupporterDetection(originalVersion: "1.1", platform: "macOS", detectedAt: Date())
        let manager = EntitlementManager(
            store: InMemoryEarlySupporterStore(detection),
            ui: EntitlementUIModel())
        await manager.refresh()
        #expect(await manager.currentTier == .plus)
        #expect(await manager.source == .earlySupporter)
        #expect(await manager.allows(.unlimitedKnowledge))
    }

    @Test func noGrantWithoutKeychainItem() async {
        let manager = EntitlementManager(store: InMemoryEarlySupporterStore(), ui: EntitlementUIModel())
        await manager.refresh()
        #expect(await manager.currentTier == .free)
    }
}

@Suite("M2 — StoreKit flows (buy / lapse / lifetime)", .serialized, .enabled(if: storeKitFlowsEnabled))
@MainActor
struct StoreKitFlowTests {
    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(contentsOf:
            repoRoot.appendingPathComponent("Molten/Entitlements/Molten.storekit"))
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    private func makeManager() -> EntitlementManager {
        EntitlementManager(store: InMemoryEarlySupporterStore(), ui: EntitlementUIModel())
    }

    /// StoreKit transaction propagation is asynchronous and shares the
    /// process with the host app's own entitlement listener — poll instead
    /// of assuming a fixed delay.
    private func waitForTier(_ manager: EntitlementManager, _ expected: Tier, timeout: TimeInterval = 6) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            await manager.refresh()
            if await manager.currentTier == expected { return true }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    @Test func monthlyPurchaseGrantsPlus() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try session.buyProduct(productIdentifier: "molten.plus.monthly")
        let manager = makeManager()
        #expect(await waitForTier(manager, .plus))
        #expect(await manager.source == .subscription)
    }

    @Test func lapseFallsBackToFree() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        // Lapse = entitlements gone → Free, nothing deleted (§5.3).
        // SKTestSession.expireSubscription does not shorten the current
        // period's expirationDate in this Xcode (verified: the transaction
        // keeps its original expiry), so we remove the entitlements entirely
        // — the app-side path is identical: no active entitlement → Free.
        // The future-expiration requirement itself is enforced in
        // EntitlementManager.refresh (nil/past expirations never grant).
        try session.buyProduct(productIdentifier: "molten.plus.monthly")
        let manager = makeManager()
        #expect(await waitForTier(manager, .plus))
        session.clearTransactions()
        #expect(await waitForTier(manager, .free))
        #expect(await !manager.allows(.iCloudKnowledge))
    }

    @Test func lifetimePurchaseGrantsPlus() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }
        try session.buyProduct(productIdentifier: "molten.plus.lifetime")
        let manager = makeManager()
        #expect(await waitForTier(manager, .plus))
        #expect(await manager.source == .lifetime)
    }

    #if DEBUG
    @Test func simulatedEarlySupporterWithSubscription() async throws {
        let session = try makeSession()
        defer {
            session.clearTransactions()
            EarlySupporterDetector.simulateEarlySupporter = false
        }
        try session.buyProduct(productIdentifier: "molten.plus.monthly")
        EarlySupporterDetector.simulateEarlySupporter = true // M3 debug toggle
        let manager = makeManager()
        #expect(await waitForTier(manager, .plus))
        #expect(await manager.source == .earlySupporter)
    }
    #endif
}

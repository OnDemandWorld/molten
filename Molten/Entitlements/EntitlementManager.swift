//
//  EntitlementManager.swift
//  Molten
//
//  Molten 2.0 — M8/M9/M11/M12. Single source of truth for the current tier.
//  currentTier = max(earlySupporter ? .plus : .free, active subscription,
//  lifetime). Listens to Transaction.updates from launch; works offline via
//  StoreKit cached entitlements + the M4 Keychain item.
//

import Foundation
import Observation
import StoreKit

@MainActor @Observable
final class EntitlementUIModel {
    static let shared = EntitlementUIModel()

    var tier: Tier = .free
    var source: EntitlementSource = .none
    var renewalDate: Date?
    /// M5: one-time thank-you sheet for Early Supporters.
    var showEarlySupporterThankYou = false

    func apply(tier: Tier, source: EntitlementSource, renewalDate: Date?) {
        // Only notify on real changes: unconditional assignment fires
        // @Observable on every refresh, re-rendering observers (e.g. the
        // Settings subscription section) and tearing down sheets anchored
        // to them — the paywall closed itself on first presentation.
        if self.tier != tier { self.tier = tier }
        if self.source != source { self.source = source }
        if self.renewalDate != renewalDate { self.renewalDate = renewalDate }
    }
}

actor EntitlementManager {
    @MainActor static let shared = EntitlementManager(
        store: EntitlementKeychain.shared, ui: EntitlementUIModel.shared)

    private(set) var currentTier: Tier = .free
    private(set) var source: EntitlementSource = .none
    private(set) var renewalDate: Date?

    private let store: EarlySupporterStoring
    private let ui: EntitlementUIModel
    private var updatesTask: Task<Void, Never>?
    private var earlySupporter = false

    init(store: EarlySupporterStoring, ui: EntitlementUIModel) {
        self.store = store
        self.ui = ui
    }

    /// M8: start listening at launch, then evaluate once.
    func start() async {
        if updatesTask == nil {
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result else { continue }
                    await transaction.finish()
                    await self?.refresh()
                }
            }
        }
        await refresh()
    }

    /// M1/M4/M11: AppTransaction first, Keychain fallback when offline.
    func refresh() async {
        if let detection = await EarlySupporterDetector.detect() {
            earlySupporter = true
            _ = store.save(detection)
        } else {
            earlySupporter = store.load() != nil
        }

        var subscriptionTier: Tier?
        var lifetime = false
        var renewal: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            switch tx.productID {
            case "molten.plus.monthly", "molten.plus.yearly":
                // Subscriptions grant only with a future expiration; a nil
                // or past expiration never grants (lapse policy, §5.3).
                if let expiration = tx.expirationDate, expiration > Date() {
                    subscriptionTier = .plus
                    renewal = expiration
                }
            case "molten.pro.monthly", "molten.pro.yearly": // reserved (M15)
                if let expiration = tx.expirationDate, expiration > Date() {
                    subscriptionTier = .pro
                    renewal = expiration
                }
            case "molten.plus.lifetime":
                lifetime = true
            default:
                break
            }
        }

        // M8: max of the three grant paths.
        let (tier, src) = Self.computeTier(
            earlySupporter: earlySupporter,
            subscriptionTier: subscriptionTier,
            lifetime: lifetime)

        currentTier = tier
        source = src
        renewalDate = subscriptionTier != nil ? renewal : nil

        // M5: one-time thank-you sheet.
        let thanked = UserDefaults.standard.bool(forKey: "earlySupporterThankYouShown")
        let showThankYou = earlySupporter && !thanked

        await ui.apply(tier: tier, source: src, renewalDate: renewalDate)
        if showThankYou {
            await MainActor.run { ui.showEarlySupporterThankYou = true }
        }
    }

    /// M8 tier math, pure for unit testing (M6).
    static func computeTier(
        earlySupporter: Bool,
        subscriptionTier: Tier?,
        lifetime: Bool
    ) -> (Tier, EntitlementSource) {
        let tier = max(
            earlySupporter ? .plus : .free,
            subscriptionTier ?? .free,
            lifetime ? .plus : .free)
        let src: EntitlementSource = earlySupporter
            ? .earlySupporter
            : (subscriptionTier != nil ? .subscription : (lifetime ? .lifetime : .none))
        return (tier, src)
    }

    /// M9: the only gate API. No ad-hoc isPlus checks elsewhere.
    func allows(_ feature: Feature) -> Bool {
        currentTier >= feature.requiredTier
    }

    /// M12: Restore. (StoreKit.AppStore qualified — Molten has its own AppStore.)
    func restore() async {
        try? await AppTransaction.refresh()
        try? await StoreKit.AppStore.sync()
        await refresh()
    }

    /// M5: mark the thank-you sheet as shown.
    func acknowledgeThankYou() {
        UserDefaults.standard.set(true, forKey: "earlySupporterThankYouShown")
    }
}

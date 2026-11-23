//
//  UpsellCoordinator.swift
//  Molten
//
//  "Getting more people to subscribe to Molten, without ads" — soft upsell
//  prompts with hard frequency rules. All counters are local (dedicated
//  UserDefaults suite); nothing leaves the device, so the no-telemetry
//  promise holds. Paying users and Early Supporters never see prompts.
//
//  Rules (encoded, not guidelines):
//  - at most one soft prompt every 14 days, at most 4 ever;
//  - never at launch UI, during streaming, in the floating panel, from the
//    share extension (separate process), or in a session that showed the
//    hard paywall;
//  - paying tiers and opt-out suppress everything;
//  - inline cards preferred; full-screen sheets only for settled-in,
//    lapse, and supporter moments.
//

import Foundation
import SwiftUI

@MainActor @Observable
final class UpsellCoordinator {
    static let shared = UpsellCoordinator()

    enum Prompt: String, Identifiable {
        case groundedAnswer   // inline card under the first cited reply
        case settledIn        // sheet: 3 active days + 30 messages + day 5
        case subscriptionLapsed
        case panelThanks      // supporter-style, after 20 panel uses
        var id: String { rawValue }
    }

    // MARK: UI state (observed by ApplicationEntry / ChatMessageView)

    /// Full-screen soft sheet, if one is due.
    var activeSheet: Prompt?
    /// Inline card under the reply with this message ID.
    var groundedCardMessageID: UUID?
    /// Central paywall presentation for upsell entry points.
    var showPaywall = false
    /// First prompt's dismiss offers "Don't show tips like this again".
    var offerOptOut = false

    // MARK: Rules

    /// Release dial ("without ads" doc: ship one trigger per version to
    /// measure which helped via App Store Connect). Trim this set per
    /// release; the rules engine is unchanged.
    /// 2.0.1 (build 13): first grounded answer only. Re-enable .settledIn,
    /// .subscriptionLapsed, .panelThanks in later builds to measure each.
    static var enabledTriggers: Set<Prompt> = [.groundedAnswer]

    static let cooldownDays = 14
    static let maxPrompts = 4
    static let settledActiveDays = 3
    static let settledMessages = 30
    static let settledMinInstallDays = 5
    static let panelThanksThreshold = 20

    // Injectable for unit tests (defaults keep production wiring).
    var currentTier: () -> Tier = { EntitlementUIModel.shared.tier }
    var isStreaming: () -> Bool = { ConversationStore.shared.conversationState == .loading }
    #if os(macOS)
    var isPanelActive: () -> Bool = { NSApp.keyWindow is FloatingPanel }
    #else
    var isPanelActive: () -> Bool = { false }
    #endif

    private let defaults: UserDefaults
    private var hardPaywallThisSession = false
    private var promptedThisSession = false

    init(defaults: UserDefaults = UserDefaults(suiteName: "molten.upsell") ?? .standard) {
        self.defaults = defaults
    }

    // MARK: Keys

    private enum Key {
        static let installDate = "installDate"
        static let activeDays = "activeDays"
        static let messages = "messages"
        static let grounded = "grounded"
        static let panelUses = "panelUses"
        static let lastPrompt = "lastPrompt"
        static let promptCount = "promptCount"
        static let optOut = "optOut"
        static let wasSubscriptionPlus = "wasSubscriptionPlus"
        static let settledShown = "settledShown"
        static let lapseShown = "lapseShown"
        static let thanksShown = "thanksShown"
    }

    // MARK: Events

    func noteEvent(_ event: Event, now: Date = Date()) {
        switch event {
        case .appLaunch:
            if defaults.object(forKey: Key.installDate) == nil {
                defaults.set(now, forKey: Key.installDate)
            }
            recordActiveDay(now)
            evaluateLapse(now: now)
            evaluateSettled(now: now)
        case .messageSent:
            defaults.set(defaults.integer(forKey: Key.messages) + 1, forKey: Key.messages)
            evaluateSettled(now: now)
        case .panelUse:
            let uses = defaults.integer(forKey: Key.panelUses) + 1
            defaults.set(uses, forKey: Key.panelUses)
            if uses == Self.panelThanksThreshold, !defaults.bool(forKey: Key.thanksShown) {
                present(.panelThanks, now: now)
            }
        }
    }

    enum Event { case appLaunch, messageSent, panelUse }

    /// First grounded answer: inline card under that reply (not a sheet).
    func noteGroundedAnswer(messageID: UUID, now: Date = Date()) {
        let count = defaults.integer(forKey: Key.grounded) + 1
        defaults.set(count, forKey: Key.grounded)
        guard count == 1, canPrompt(now: now, trigger: .groundedAnswer) else { return }
        groundedCardMessageID = messageID
        recordPrompt(now: now)
    }

    /// Track subscription history so a lapse can be acknowledged once.
    func noteTierChange(tier: Tier, source: EntitlementSource) {
        if tier >= .plus && source == .subscription {
            defaults.set(true, forKey: Key.wasSubscriptionPlus)
        }
    }

    /// Hard paywall shown this session → no soft prompts for the rest of it.
    func noteHardPaywall() {
        hardPaywallThisSession = true
    }

    // MARK: Dismissal

    func dismissPrompt() {
        activeSheet = nil
        groundedCardMessageID = nil
    }

    func optOut() {
        defaults.set(true, forKey: Key.optOut)
        dismissPrompt()
    }

    var isOptedOut: Bool { defaults.bool(forKey: Key.optOut) }

    // MARK: Trigger evaluation

    private func evaluateSettled(now: Date) {
        guard !defaults.bool(forKey: Key.settledShown),
              let install = defaults.object(forKey: Key.installDate) as? Date,
              now.timeIntervalSince(install) >= Double(Self.settledMinInstallDays) * 86400,
              activeDayCount >= Self.settledActiveDays,
              defaults.integer(forKey: Key.messages) >= Self.settledMessages
        else { return }
        defaults.set(true, forKey: Key.settledShown)
        present(.settledIn, now: now)
    }

    private func evaluateLapse(now: Date) {
        guard !defaults.bool(forKey: Key.lapseShown),
              defaults.bool(forKey: Key.wasSubscriptionPlus),
              currentTier() == .free
        else { return }
        defaults.set(true, forKey: Key.lapseShown)
        present(.subscriptionLapsed, now: now)
    }

    // MARK: Frequency rules

    private func canPrompt(now: Date, trigger: Prompt? = nil) -> Bool {
        if let trigger, !Self.enabledTriggers.contains(trigger) { return false }
        guard currentTier() == .free, !isOptedOut else { return false }
        guard !hardPaywallThisSession, !promptedThisSession else { return false }
        guard defaults.integer(forKey: Key.promptCount) < Self.maxPrompts else { return false }
        if let last = defaults.object(forKey: Key.lastPrompt) as? Date,
           now.timeIntervalSince(last) < Double(Self.cooldownDays) * 86400 {
            return false
        }
        guard !isStreaming(), !isPanelActive() else { return false }
        return true
    }

    private func present(_ prompt: Prompt, now: Date) {
        guard canPrompt(now: now, trigger: prompt) else { return }
        activeSheet = prompt
        recordPrompt(now: now)
    }

    private func recordPrompt(now: Date) {
        defaults.set(now, forKey: Key.lastPrompt)
        let count = defaults.integer(forKey: Key.promptCount) + 1
        defaults.set(count, forKey: Key.promptCount)
        promptedThisSession = true
        offerOptOut = count == 1
    }

    // MARK: Active days

    private var activeDayCount: Int {
        (defaults.array(forKey: Key.activeDays) as? [String])?.count ?? 0
    }

    private func recordActiveDay(_ now: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar.current
        let day = formatter.string(from: now)
        var days = (defaults.array(forKey: Key.activeDays) as? [String]) ?? []
        guard !days.contains(day) else { return }
        days.append(day)
        // Bounded: only the count matters.
        if days.count > 400 { days.removeFirst(days.count - 400) }
        defaults.set(days, forKey: Key.activeDays)
    }
}
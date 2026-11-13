//
//  SubscriptionSettingsSection.swift
//  Molten
//
//  Molten 2.0 — M13. Settings ▸ Subscription: tier, source, renewal date,
//  Manage Subscription link, Restore. M3 DEBUG-only simulate toggle.
//

import SwiftUI
import StoreKit

struct SubscriptionSettingsSection: View {
    @State private var ui = EntitlementUIModel.shared

    var body: some View {
        Section("Subscription") {
            LabeledContent("Plan") { Text(planText) }
            if let renewal = ui.renewalDate {
                LabeledContent("Renews") { Text(renewal, style: .date) }
            }
            Button("Restore Purchases") {
                Task { await EntitlementManager.shared.restore() }
            }
            Link("Manage Subscription",
                 destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            #if DEBUG
            // M3: the only way to simulate Early Supporter in sandbox/Xcode.
            Toggle("Simulate Early Supporter", isOn: Binding(
                get: { EarlySupporterDetector.simulateEarlySupporter },
                set: { newValue in
                    EarlySupporterDetector.simulateEarlySupporter = newValue
                    Task { await EntitlementManager.shared.refresh() }
                }))
            #endif
        }
    }

    private var planText: String {
        switch (ui.tier, ui.source) {
        case (.plus, .earlySupporter):
            return "Molten Plus — Early Supporter (lifetime)" // M5
        case (.plus, .subscription):
            return "Molten Plus"
        case (.plus, .lifetime):
            return "Molten Plus — Lifetime"
        case (.pro, _):
            return "Molten Pro"
        default:
            return "Free"
        }
    }
}

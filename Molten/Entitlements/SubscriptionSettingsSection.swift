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
    // Presentation state lives in SettingsView (sheets anchored to Form
    // sections get torn down by the Form's update cycle).
    @Binding var showPaywall: Bool
    @Binding var showPlanDetail: Bool

    var body: some View {
        Section("Subscription") {
            // Tapping Plan: Free → paywall (explicit upgrade path); Plus →
            // plan details + management. Never an unsolicited paywall (M10).
            Button {
                if ui.tier == .free {
                    showPaywall = true
                } else {
                    showPlanDetail = true
                }
            } label: {
                HStack {
                    Text("Plan")
                    Spacer()
                    Text(planText)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
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

/// Plus users tapping Plan: details + management, not a sales pitch.
struct PlanDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var ui = EntitlementUIModel.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text(planTitle)
                .font(.title3.bold())
            if ui.source == .earlySupporter {
                Text("Thank you for supporting Molten. Plus is yours forever — every Plus feature we ship, at no cost.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let renewal = ui.renewalDate {
                Text("Renews \(renewal, style: .date)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 10) {
                Link("Manage Subscription",
                     destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                Button("Restore Purchases") {
                    Task { await EntitlementManager.shared.restore() }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .font(.callout)
        }
        .padding(28)
        .frame(minWidth: 320)
    }

    private var planTitle: String {
        switch ui.source {
        case .earlySupporter: return "Molten Plus — Early Supporter"
        case .lifetime: return "Molten Plus — Lifetime"
        case .subscription: return "Molten Plus"
        default: return "Molten"
        }
    }
}

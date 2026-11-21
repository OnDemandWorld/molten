//
//  EarlySupporterThankYouView.swift
//  Molten
//
//  Molten 2.0 — M5. One-time thank-you sheet; exact public wording (§5.4).
//

import SwiftUI

struct EarlySupporterThankYouView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.fill")
                .font(.system(size: 40))
                .foregroundStyle(.pink)
            Text("Thank you, Early Supporter") // earlySupporter.title
                .font(.title2.bold())
            Text("Everyone who bought Molten before 2.0 gets Molten Plus forever: every Plus feature we ship, at no cost. Pro will be a separate, optional upgrade.") // earlySupporter.body
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Continue") {
                Task {
                    await EntitlementManager.shared.acknowledgeThankYou()
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: 420)
    }
}

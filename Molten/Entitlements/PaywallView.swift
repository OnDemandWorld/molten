//
//  PaywallView.swift
//  Molten
//
//  Molten 2.0 — M10. Shown ONLY when the user reaches a Plus limit, never at
//  launch. SubscriptionStoreView + lifetime purchase. The amount actually
//  billed is the most prominent price; no monthly-equivalent marketing.
//  The layout is configuration-driven so a Pro column can be added later
//  without a rewrite (M15).
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    /// Products shown in the subscription column. Pro products are appended
    /// here when Pro launches (configuration, not rewrite — M15).
    static let subscriptionProductIDs = ["molten.plus.yearly", "molten.plus.monthly"]
    static let lifetimeProductID = "molten.plus.lifetime"

    @Environment(\.dismiss) private var dismiss
    @State private var lifetimeProduct: Product?
    @State private var purchasing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Molten Plus: your documents, on all your devices") // paywall.headline
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            SubscriptionStoreView(productIDs: Self.subscriptionProductIDs)
                .storeButton(.visible, for: .restorePurchases)
                .onInAppPurchaseCompletion { _, result in
                    if case .success(.success(.verified(let transaction))) = result {
                        await transaction.finish()
                        await EntitlementManager.shared.refresh()
                        dismiss()
                    }
                }

            if let product = lifetimeProduct {
                Button {
                    purchaseLifetime(product)
                } label: {
                    VStack(spacing: 2) {
                        Text("Lifetime — \(product.displayPrice)")
                            .font(.headline)
                        Text("One purchase. Plus forever.")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(purchasing)
                .padding(.horizontal)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 16) {
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy", destination: URL(string: "https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md")!)
            }
            .font(.caption)
            .padding(.bottom, 16)
        }
        .task {
            lifetimeProduct = try? await Product.products(for: [Self.lifetimeProductID]).first
        }
    }

    private func purchaseLifetime(_ product: Product) {
        purchasing = true
        errorMessage = nil
        Task {
            defer { purchasing = false }
            do {
                let result = try await product.purchase()
                switch result {
                case .success(let verification):
                    if case .verified(let transaction) = verification {
                        await transaction.finish()
                        await EntitlementManager.shared.refresh()
                        dismiss()
                    }
                case .userCancelled, .pending:
                    break
                @unknown default:
                    break
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

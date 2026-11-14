//
//  PaywallView.swift
//  Molten
//
//  Molten 2.0 — M10. Shown ONLY when the user reaches a Plus limit, never at
//  launch. Native Molten styling: a designed wrapper (header, feature list,
//  best-value note) around SubscriptionStoreView, plus a lifetime purchase.
//  The amount actually billed is the most prominent price (the native store
//  view and the lifetime button both show displayPrice); no per-week
//  equivalents. Configuration-driven so a Pro column can be added later
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

    private static let features: [(icon: String, text: String)] = [
        ("doc.text.magnifyingglass", "Cited answers from your own documents"),
        ("laptopcomputer.and.iphone", "Knowledge on Mac, iPhone and iPad — through your own iCloud"),
        ("arrow.triangle.2.circlepath", "Your Mac processes each file once; every device reuses it"),
        ("text.viewfinder", "OCR for scanned PDFs and images"),
        ("books.vertical", "Unlimited knowledge bases and documents"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    featureList
                    bestValueNote
                    SubscriptionStoreView(productIDs: Self.subscriptionProductIDs)
                        .storeButton(.visible, for: .restorePurchases)
                        .onInAppPurchaseCompletion { _, result in
                            if case .success(.success(.verified(let transaction))) = result {
                                await transaction.finish()
                                await EntitlementManager.shared.refresh()
                                dismiss()
                            }
                        }
                    lifetimeOption
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    footer
                }
                .padding(20)
            }
        }
        .frame(minWidth: 420, minHeight: 560)
        .task {
            lifetimeProduct = try? await Product.products(for: [Self.lifetimeProductID]).first
        }
    }

    // MARK: - Sections

    private var header: some View {
        // No close button here — the sheet already provides one at the top
        // right; a second X next to the title was redundant.
        VStack(spacing: 6) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Molten Plus")
                .font(.title2.bold())
            Text("Your documents, on all your devices") // paywall.headline
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.features, id: \.text) { feature in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: feature.icon)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 22)
                    Text(feature.text)
                        .font(.callout)
                }
            }
        }
    }

    private var bestValueNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
            Text("Best value: **Yearly** includes a **1-week free trial**.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var lifetimeOption: some View {
        if let product = lifetimeProduct {
            VStack(alignment: .leading, spacing: 6) {
                Text("Prefer to pay once?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    purchaseLifetime(product)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Plus Lifetime")
                                .font(.headline)
                            Text("One purchase. Plus forever.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(product.displayPrice)
                            .font(.headline)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(purchasing)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Subscriptions renew automatically until cancelled. Manage or cancel anytime in Settings ▸ Subscription.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Terms & Conditions", destination: ODWLegal.terms)
                Link("Privacy Policy", destination: ODWLegal.privacy)
                Link("House Rules", destination: ODWLegal.houseRules)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lifetime purchase

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

//
//  UpsellViews.swift
//  Molten
//
//  Soft-prompt surfaces for UpsellCoordinator ("without ads" doc):
//  an inline card under the first cited answer, and lightweight sheets
//  for settled-in / lapse / supporter moments. Close is always visible;
//  the first prompt offers a permanent opt-out.
//

import SwiftUI

// MARK: - Inline card (first grounded answer)

struct GroundedAnswerCard: View {
    var onSeePlus: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Color.accentColor)
                Text("Your documents, answered with citations. Plus adds unlimited bases, scanned-PDF reading and sync across devices.")
                    .font(.callout)
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            Button("Try Plus free for a week", action: onSeePlus)
                .font(.callout)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Soft sheets

struct UpsellSheetView: View {
    let prompt: UpsellCoordinator.Prompt
    @Environment(\.dismiss) private var dismiss
    @State private var coordinator = UpsellCoordinator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button {
                    coordinator.dismissPrompt()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            if prompt == .settledIn {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Unlimited knowledge bases and documents", systemImage: "books.vertical")
                    Label("OCR for scanned PDFs and images", systemImage: "text.viewfinder")
                    Label("Process once on Mac, read on every device — through your own iCloud", systemImage: "laptopcomputer.and.iphone")
                }
                .font(.callout)
            }
            HStack {
                Button(primaryTitle) {
                    coordinator.dismissPrompt()
                    dismiss()
                    coordinator.showPaywall = true
                }
                .buttonStyle(.borderedProminent)
                Button("Not now") {
                    coordinator.dismissPrompt()
                    dismiss()
                }
            }
            // First prompt only: a permanent, respected opt-out.
            if coordinator.offerOptOut {
                Button("Don't show tips like this again") {
                    coordinator.optOut()
                    dismiss()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text("Molten has no ads, no tracking, no investors. Plus keeps it that way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(maxWidth: 460)
    }

    private var title: String {
        switch prompt {
        case .settledIn: return "What you get with Plus"
        case .subscriptionLapsed: return "Sync is paused"
        case .panelThanks: return "Thank you for using Molten"
        case .groundedAnswer: return "Molten Plus"
        }
    }

    private var message: String {
        switch prompt {
        case .settledIn:
            return "You've made Molten part of your routine. Try Plus free for a week — cancel anytime."
        case .subscriptionLapsed:
            return "Your documents are all still here, on this device. Resubscribe to sync them across your devices again."
        case .panelThanks:
            return "You've used the quick panel 20 times — thank you. The panel and chat stay free forever; Plus funds development and adds Knowledge superpowers."
        case .groundedAnswer:
            return "Your documents, on all your devices."
        }
    }

    private var primaryTitle: String {
        switch prompt {
        case .subscriptionLapsed: return "Resubscribe"
        case .panelThanks: return "See Plus"
        default: return "Try free for a week"
        }
    }
}
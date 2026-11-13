//
//  KnowledgeViews.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import SwiftUI

/// K-U stubs. M3 wires these into the sidebar and composer.
struct KnowledgeSidebar: View {
    var body: some View { Text("Knowledge") }
}

struct BaseDetailView: View {
    var body: some View { Text("Knowledge base") }
}

struct CitationChips: View {
    var body: some View { EmptyView() }
}

struct KnowledgeOnboarding: View {
    var body: some View {
        // knowledge.onboarding.privacy — Appendix B (P2)
        Text("Your files sync with your own iCloud account. Molten has no servers. For end-to-end encryption, turn on Advanced Data Protection.")
    }
}

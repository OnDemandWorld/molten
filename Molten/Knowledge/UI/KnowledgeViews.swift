//
//  KnowledgeViews.swift
//  Molten
//
//  Molten 2.0 — M3. Knowledge sidebar (K-U1), base detail (K-U2),
//  onboarding (K-U6/P2), citation chips (K-R5).
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Sidebar (K-U1)

struct KnowledgeSidebar: View {
    @State private var bases: [BaseID] = []
    @State private var counts: [BaseID: Int] = [:]
    @State private var showOnboarding = false
    @State private var showPaywall = false
    @State private var newBaseName = ""
    @State private var showNewBase = false
    @State private var indexing = false
    @State private var selectedBase: BaseID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Knowledge")
                    .font(.headline)
                Spacer()
                Button {
                    attemptNewBase()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New knowledge base")
            }
            ForEach(bases, id: \.self) { base in
                Button {
                    selectedBase = base
                } label: {
                    HStack {
                        Image(systemName: "books.vertical")
                        VStack(alignment: .leading) {
                            Text(base).font(.body)
                            Text("\(counts[base] ?? 0) documents")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if bases.isEmpty {
                Text("Drop files into a folder to add them to a knowledge base.") // knowledge.rootFileHint
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .sheet(isPresented: $showOnboarding) { KnowledgeOnboarding() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: Binding(
            get: { selectedBase != nil },
            set: { if !$0 { selectedBase = nil } })) {
            if let base = selectedBase { BaseDetailView(base: base) }
        }
        .alert("New knowledge base", isPresented: $showNewBase) {
            TextField("Name", text: $newBaseName)
            Button("Create") { createBase() }
            Button("Cancel", role: .cancel) {}
        }
        .task { await refresh() }
    }

    private func refresh() async {
        bases = await KnowledgeStore.shared.bases()
        for base in bases {
            counts[base] = await KnowledgeStore.shared.documentCount(base: base)
        }
    }

    private func attemptNewBase() {
        Task {
            let unlimited = await EntitlementManager.shared.allows(.unlimitedKnowledge)
            if KnowledgeLimits.canCreateBase(existing: bases.count, unlimited: unlimited) {
                showNewBase = true
            } else {
                showPaywall = true // K-U5: over a limit opens the paywall
            }
        }
    }

    private func createBase() {
        let name = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newBaseName = ""
        Task {
            try? FileManager.default.createDirectory(
                at: KnowledgeContainer.baseDirectory(name), withIntermediateDirectories: true)
            await KnowledgeStore.shared.createBase(name)
            await refresh()
            if bases.count == 1 { showOnboarding = true }
        }
    }
}

// MARK: - Base detail (K-U2)

struct BaseDetailView: View {
    let base: BaseID
    @State private var files: [URL] = []
    @State private var importing = false
    @State private var indexing = false
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(base).font(.title2.bold())
                Spacer()
                Button("Add files…") { importing = true }
                Button(indexing ? "Indexing…" : "Process now") {
                    process(force: true) // K-P3: overrides Waiting for Mac
                }
                .disabled(indexing)
                // K-R1: attach this base to the open conversation.
                Button("Attach to chat") {
                    Task { @MainActor in
                        ConversationStore.shared.selectedConversation?.attachedKnowledgeBase = base
                        status = "Attached to the current chat"
                    }
                }
                #if os(macOS)
                Button("Open in Finder") {
                    NSWorkspace.shared.open(KnowledgeContainer.baseDirectory(base))
                }
                #endif
            }
            .padding()
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary).padding(.horizontal)
            }
            List(files, id: \.path) { file in
                HStack {
                    Image(systemName: "doc")
                    Text(file.lastPathComponent)
                    Spacer()
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .plainText, .rtf, .html, .png, .jpeg, UTType("org.openxmlformats.wordprocessingml.document") ?? .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { addFiles(urls) }
        }
        .task { loadFiles() }
    }

    private func loadFiles() {
        let dir = KnowledgeContainer.baseDirectory(base)
        files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    }

    private func addFiles(_ urls: [URL]) {
        Task {
            let unlimited = await EntitlementManager.shared.allows(.unlimitedKnowledge)
            let existing = await KnowledgeStore.shared.documentCount(base: base)
            var added = 0
            for url in urls {
                guard KnowledgeLimits.canAddDocument(existing: existing + added, unlimited: unlimited) else { break }
                let secured = url.startAccessingSecurityScopedResource()
                defer { if secured { url.stopAccessingSecurityScopedResource() } }
                let dest = KnowledgeContainer.baseDirectory(base).appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: dest)
                added += 1
            }
            loadFiles()
            process()
        }
    }

    private func process(force: Bool = false) {
        indexing = true
        Task {
            // K-P3: defer to a fresh Mac unless the user forces processing.
            let deferring = await KnowledgeIndexer.shared.shouldDefer()
            if !force && deferring {
                status = "Waiting for Mac" // knowledge.status.waitingForMac
                indexing = false
                return
            }
            status = "Processing…"
            #if os(iOS)
            KnowledgeBackgroundTask.schedule() // K-P6: user-action long job
            #endif
            // Model download happens once on first Knowledge use (K-E3).
            try? await EmbeddingService.shared.ensureModel { _ in }
            do {
                try await KnowledgeIndexer.shared.scan(base: base, force: force)
                let count = await KnowledgeStore.shared.documentCount(base: base)
                status = "\(count) documents indexed"
            } catch {
                status = "Error: \(error.localizedDescription) — tap Process now to retry"
            }
            indexing = false
        }
    }
}

// MARK: - Onboarding (K-U6 / P2)

struct KnowledgeOnboarding: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your private knowledge base").font(.title2.bold())
            Label("One folder per base. Drop PDFs, text, Markdown, RTF, HTML, DOCX or images into the base folder; Molten indexes them for cited answers.", systemImage: "folder")
            Label("The embedding model (~480 MB) downloads once per device. Until then, keyword search works.", systemImage: "arrow.down.circle")
            Label("On Mac + iPhone/iPad with Plus, your Mac does the heavy processing and the results sync through your own iCloud.", systemImage: "laptopcomputer.and.iphone")
            // knowledge.onboarding.privacy — Appendix B (P2)
            Text("Your files sync with your own iCloud account. Molten has no servers. For end-to-end encryption, turn on Advanced Data Protection.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Got it") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: 480)
    }
}

// MARK: - Processing settings (K-P3/K-P4)

struct KnowledgeSettingsSection: View {
    @AppStorage("knowledgeKeepIndexing") private var keepIndexing = true
    @AppStorage("knowledgeLetMacDoIt") private var letMacDoIt = true
    @AppStorage("knowledgeProcessingPolicy") private var policy = ProcessingPolicy.bothWhileCharging.rawValue

    var body: some View {
        Section("Knowledge") {
            #if os(macOS)
            Toggle("Keep indexing while Molten is open", isOn: $keepIndexing)
            #else
            Toggle("Let my Mac do the heavy lifting", isOn: $letMacDoIt)
            Picker("Processing on this device", selection: $policy) {
                Text("Both stages while charging").tag(ProcessingPolicy.bothWhileCharging.rawValue)
                Text("Always both stages").tag(ProcessingPolicy.alwaysBoth.rawValue)
            }
            #endif
        }
    }
}

// MARK: - Citation chips (K-R5)

struct CitationRef: Codable, Sendable, Identifiable {
    var id: String { "\(sourceName)#\(page ?? 0)#\(charStart)" }
    let sourceName: String
    let page: Int?
    let charStart: Int
    let charEnd: Int
    let base: String
}

struct CitationChips: View {
    let citations: [CitationRef]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(citations.enumerated()), id: \.offset) { index, citation in
                Button {
                    open(citation)
                } label: {
                    Text("[\(index + 1)] \(citation.sourceName)\(citation.page.map { ", p.\($0)" } ?? "")")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open source \(citation.sourceName)")
            }
        }
    }

    private func open(_ citation: CitationRef) {
        let dir = KnowledgeContainer.baseDirectory(citation.base)
        let file = dir.appendingPathComponent(citation.sourceName)
        #if os(macOS)
        NSWorkspace.shared.open(file)
        #else
        UIApplication.shared.open(file)
        #endif
    }
}

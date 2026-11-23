//
//  KnowledgeViews.swift
//  Molten
//
//  Molten 2.0 — M3. Knowledge sidebar (K-U1), base detail (K-U2),
//  onboarding (K-U6/P2), citation chips (K-R5).
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Base status (K-U1 vocabulary)

enum BaseStatus {
    /// Indexed · Processing n/m · Text ready, semantic search pending ·
    /// Waiting for Mac · Needs re-index · Error
    static func label(documents: Int, files: Int, chunks: Int, vectors: Int, waitingForMac: Bool, processing: Bool, error: String?) -> String {
        if let error { return "Error: \(error)" }
        if waitingForMac { return "Waiting for Mac" }
        if processing { return "Processing \(documents)/\(files)" }
        if documents == 0 { return "Empty" }
        if files > documents { return "Needs re-index" }
        if chunks > 0 && vectors == 0 { return "Text ready — semantic search pending" }
        if vectors > 0 && vectors < chunks { return "Processing \(vectors)/\(chunks)" }
        return "Indexed"
    }
}

// MARK: - Sidebar (K-U1)

struct KnowledgeSidebar: View {
    /// iOS: closes the sliding sidebar after "Use in Chat" so the user
    /// lands directly in the conversation.
    var onUseInChat: (() -> Void)? = nil
    @State private var bases: [BaseID] = []
    @State private var counts: [BaseID: Int] = [:]
    @State private var showOnboarding = false
    @State private var showPaywall = false
    @State private var newBaseName = ""
    @State private var showNewBase = false
    @State private var selectedBase: BaseID?
    @State private var baseError: String?

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
            if let baseError {
                Text(baseError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 8)
        .sheet(isPresented: $showOnboarding) { KnowledgeOnboarding() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: Binding(
            get: { selectedBase != nil },
            set: { if !$0 { selectedBase = nil } }),
            onDismiss: {
                // Adding/removing documents in the detail sheet mutates the
                // store; re-query so the sidebar count doesn't stay stale.
                Task { await refresh() }
            }) {
            if let base = selectedBase { BaseDetailView(base: base, onUseInChat: onUseInChat) }
        }
        .alert("New knowledge base", isPresented: $showNewBase) {
            TextField("Name", text: $newBaseName)
            Button("Create") { createBase() }
            Button("Cancel", role: .cancel) {}
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let currentBases = await KnowledgeStore.shared.bases()
        var newCounts: [BaseID: Int] = [:]
        for base in currentBases {
            newCounts[base] = await KnowledgeStore.shared.documentCount(base: base)
        }
        // Assign together and drop counts for bases that no longer exist.
        bases = currentBases
        counts = newCounts
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
        // G3 (review 2026-11-24): validate the name (no ".."/"/"/hidden
        // folders) and only register the base if the folder was created.
        guard let name = ShareImport.sanitizedBaseName(newBaseName) else {
            baseError = "Invalid name — avoid “/”, “..”, and leading dots."
            return
        }
        newBaseName = ""
        baseError = nil
        Task {
            do {
                try FileManager.default.createDirectory(
                    at: KnowledgeContainer.baseDirectory(name), withIntermediateDirectories: true)
            } catch {
                baseError = "Could not create base: \(error.localizedDescription)"
                return
            }
            await KnowledgeStore.shared.createBase(name)
            await refresh()
            if bases.count == 1 { showOnboarding = true }
        }
    }
}

// MARK: - Base detail (K-U2)

struct BaseDetailView: View {
    let base: BaseID
    /// iOS: closes the sliding sidebar after "Use in Chat".
    var onUseInChat: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var files: [URL] = []
    @State private var importing = false
    @State private var indexing = false
    @State private var status = ""
    @State private var showDownloadConsent = false
    @State private var showPaywall = false
    @State private var fileToRemove: URL?

    var body: some View {
        NavigationStack {
            List {
                if files.isEmpty {
                    Text("No files yet. Add PDFs, text, Markdown, RTF, HTML, DOCX or images.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(files, id: \.path) { file in
                        HStack(spacing: 10) {
                            Image(systemName: Self.isPlaceholder(file) ? "icloud" : "doc")
                                .foregroundStyle(.secondary)
                            Text(Self.displayName(file))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                fileToRemove = file
                            } label: {
                                Label("Remove from Base", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete { offsets in
                        if let first = offsets.first { fileToRemove = files[first] }
                    }
                }
            }
            .navigationTitle(base)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            process(force: true) // K-P3: overrides Waiting for Mac
                        } label: {
                            Label(indexing ? "Indexing…" : "Process Now",
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(indexing)
                        #if os(macOS)
                        Button {
                            NSWorkspace.shared.open(KnowledgeContainer.baseDirectory(base))
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                        }
                        #endif
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More actions")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Button {
                            importing = true
                        } label: {
                            Label("Add Files", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        // K-R1: attach this base and go straight to the chat.
                        Button {
                            useInChat()
                        } label: {
                            Label("Use in Chat", systemImage: "bubble.left.and.text.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .plainText, .rtf, .html, .png, .jpeg, UTType("org.openxmlformats.wordprocessingml.document") ?? .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { addFiles(urls) }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .alert("Download embedding model?", isPresented: $showDownloadConsent) {
            Button("Download (\(ModelDownloadConsent.estimatedSizeMB) MB)") {
                ModelDownloadConsent.recordConsent()
                process(force: true)
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Semantic search needs a one-time \(ModelDownloadConsent.estimatedSizeMB) MB model download. You appear to be on cellular data. Keyword search works without it.")
        }
        .confirmationDialog(
            "Remove “\(fileToRemove.map(Self.displayName) ?? "")”?",
            isPresented: Binding(
                get: { fileToRemove != nil },
                set: { if !$0 { fileToRemove = nil } }),
            titleVisibility: .visible) {
            Button("Remove File", role: .destructive) {
                if let url = fileToRemove { removeFile(url) }
                fileToRemove = nil
            }
            Button("Cancel", role: .cancel) { fileToRemove = nil }
        } message: {
            Text("The file is deleted from this knowledge base on all your devices and removed from search.")
        }
        .task { loadFiles() }
    }

    /// Evicted iCloud files appear as hidden ".name.icloud" placeholders;
    /// show them under their real name with an iCloud badge.
    static func isPlaceholder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        return name.hasPrefix(".") && name.hasSuffix(".icloud")
    }

    static func displayName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard isPlaceholder(url) else { return name }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    // Blocking file I/O runs off the main actor (via Task.detached) so adding
    // a large PDF or a coordinated iCloud delete can't freeze the UI. These
    // helpers are nonisolated and capture only Sendable values; the calling
    // view methods marshal the results back to @State on the main actor.

    nonisolated static func enumerateFiles(in dir: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants])) ?? []
        return urls
            .filter { $0.lastPathComponent != ".DS_Store" }
            .sorted { displayName($0).localizedStandardCompare(displayName($1)) == .orderedAscending }
    }

    nonisolated static func copyImportedFiles(
        _ urls: [URL], into dir: URL, existing: Int, unlimited: Bool
    ) -> (added: Int, hitLimit: Bool, error: String?) {
        var added = 0
        var hitLimit = false
        var lastError: String?
        for url in urls {
            guard KnowledgeLimits.canAddDocument(existing: existing + added, unlimited: unlimited) else {
                hitLimit = true
                break
            }
            let secured = url.startAccessingSecurityScopedResource()
            defer { if secured { url.stopAccessingSecurityScopedResource() } }
            let dest = dir.appendingPathComponent(url.lastPathComponent)
            do {
                // Re-adding an updated file replaces the old copy.
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: url, to: dest)
                added += 1 // count only successful copies against the limit
            } catch let copyError {
                lastError = "Could not add \(url.lastPathComponent): \(copyError.localizedDescription)"
            }
        }
        return (added, hitLimit, lastError)
    }

    nonisolated static func coordinatedDelete(_ url: URL) -> Bool {
        var removed = false
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: url, options: .forDeleting, error: &coordinatorError) { newURL in
            do {
                try FileManager.default.removeItem(at: newURL)
                removed = true
            } catch {}
        }
        return removed
    }

    private func loadFiles() {
        let dir = KnowledgeContainer.baseDirectory(base)
        Task {
            let sorted = await Task.detached(priority: .userInitiated) {
                Self.enumerateFiles(in: dir)
            }.value
            files = sorted
        }
    }

    /// K-R1: attach the base to the open conversation (or start a new one),
    /// then dismiss and return to the chat.
    private func useInChat() {
        Task { @MainActor in
            let store = ConversationStore.shared
            if let conversation = store.selectedConversation {
                conversation.attachedKnowledgeBase = base
            } else {
                let conversation = ConversationSD(name: base)
                conversation.attachedKnowledgeBase = base
                // Carry the current model into the new chat so the selector
                // doesn't end up empty.
                conversation.model = LanguageModelStore.shared.selectedModel
                store.selectedConversation = conversation
                store.messages = []
                try? await store.create(conversation)
                try? await store.loadConversations()
            }
            dismiss()
            onUseInChat?()
        }
    }

    /// Delete the source file (coordinated for iCloud), drop its local
    /// mapping and index rows. Shared .mkt/.mkv outputs are left for the
    /// 7-day grace cleanup (K-P10) — other devices may still reference them.
    private func removeFile(_ url: URL) {
        Task {
            let name = Self.displayName(url)
            let realPath = KnowledgeContainer.baseDirectory(base)
                .appendingPathComponent(name).path
            let entry = await FileMapping.shared.entry(forPath: realPath)
                ?? FileMapping.shared.entry(forPath: url.path)

            let removed = await Task.detached(priority: .userInitiated) {
                Self.coordinatedDelete(url)
            }.value
            guard removed else {
                status = "Could not remove \(name)"
                return
            }
            await FileMapping.shared.remove(path: realPath)
            await FileMapping.shared.remove(path: url.path)
            // Always drop this base's index row for the removed file. The
            // hash + "still referenced" gate alone left stale rows whenever
            // the mapping held duplicate path keys for the same content
            // (path/Unicode normalization) or another entry shared the hash —
            // the document count then never decreased.
            await KnowledgeStore.shared.removeDocument(base: base, name: name)
            if let hash = entry?.hash {
                let stillReferenced = await FileMapping.shared.referencedHashes().contains(hash)
                if !stillReferenced {
                    await KnowledgeStore.shared.removeDocument(hash: hash)
                }
            }
            loadFiles()
            status = "Removed \(name)"
        }
    }

    /// G1 (review 2026-11-24): the Free limit must count files PRESENT in
    /// the base, not indexed documents — on iOS processing defers to Mac,
    /// so the indexed count stays 0 and the paywall never fired.
    nonisolated static func countFiles(in dir: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return 0 }
        var count = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    private func addFiles(_ urls: [URL]) {
        Task {
            let unlimited = await EntitlementManager.shared.allows(.unlimitedKnowledge)
            let dir = KnowledgeContainer.baseDirectory(base)
            let existing = await Task.detached { Self.countFiles(in: dir) }.value
            let result = await Task.detached(priority: .userInitiated) {
                Self.copyImportedFiles(urls, into: dir, existing: existing, unlimited: unlimited)
            }.value
            if result.hitLimit { showPaywall = true } // K-U5: over a limit opens the paywall
            if let error = result.error { status = error }
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
            // K-E3: size shown + cellular confirmation before the one-time
            // model download.
            do {
                try await ModelDownloadConsent.check()
            } catch {
                status = ""
                indexing = false
                showDownloadConsent = true
                return
            }
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

// MARK: - Chat attachment indicator (K-R1)

/// Shows which knowledge base grounds the open conversation, with a
/// one-tap detach. Without this, "Use in Chat" had no visible effect.
struct KnowledgeAttachmentBanner: View {
    let conversation: ConversationSD?

    var body: some View {
        if let base = conversation?.attachedKnowledgeBase {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical.fill")
                    .font(.caption)
                Text("Knowledge: \(base)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    conversation?.attachedKnowledgeBase = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Detach knowledge base")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: Capsule())
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

// MARK: - Conversations settings (C2/C3/X1)

struct ConversationsSettingsSection: View {
    @AppStorage("autoTitles") private var autoTitles = true
    @AppStorage("swamaContextWindow") private var swamaContextWindow = ContextWindow.defaultWindow
    @State private var exporting = false
    @State private var importing = false
    @State private var status = ""
    @State private var includeAnalytics = true

    var body: some View {
        Section("Conversations") {
            Toggle("Auto-generate titles", isOn: $autoTitles)
            Stepper("OpenAI-compatible context window: \(swamaContextWindow)",
                    value: $swamaContextWindow, in: 1024...131072, step: 1024)
            Toggle("Include analytics in exports", isOn: $includeAnalytics)
            Button("Export all conversations (zip)") { exporting = true }
            Button("Import conversations (JSON)") { importing = true }
            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fileExporter(isPresented: $exporting, document: ZipDocument(), contentType: .zip, defaultFilename: "Molten-Conversations") { result in
            if case .success(let url) = result {
                Task {
                    // Review 2026-11-24: report failures instead of a fake
                    // success, and keep the heavy zip work off the main actor.
                    do {
                        let conversations = try await SwiftDataService.shared.fetchConversations()
                        let exported = conversations.map {
                            Exporter.exported($0, includeAnalytics: includeAnalytics)
                        }
                        let data = try await Task.detached {
                            try Exporter.zipAll(exported: exported)
                        }.value
                        try data.write(to: url)
                        status = "Exported \(conversations.count) conversations"
                    } catch {
                        // Don't leave the 0-byte ZipDocument placeholder behind.
                        try? FileManager.default.removeItem(at: url)
                        status = "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    do {
                        let data = try await Task.detached { () -> Data in
                            let secured = url.startAccessingSecurityScopedResource()
                            defer { if secured { url.stopAccessingSecurityScopedResource() } }
                            return try Data(contentsOf: url)
                        }.value
                        let count = try await Importer.importJSON(data)
                        status = "Imported \(count) conversations"
                        try? await ConversationStore.shared.loadConversations()
                    } catch {
                        status = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}

struct ZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    init() {}
    init(configuration: ReadConfiguration) throws {}
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data())
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
    #if os(iOS)
    @State private var previewURL: URL?
    #endif

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
        #if os(iOS)
        // K-R5: files in the app container can't be opened with
        // UIApplication.open — use Quick Look.
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } })) {
            if let url = previewURL {
                QuickLookPreview(url: url)
            }
        }
        #endif
    }

    private func open(_ citation: CitationRef) {
        let dir = KnowledgeContainer.baseDirectory(citation.base)
        let file = dir.appendingPathComponent(citation.sourceName)
        #if os(macOS)
        NSWorkspace.shared.open(file)
        #else
        previewURL = file
        #endif
    }
}

#if os(iOS)
import QuickLook

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
#endif

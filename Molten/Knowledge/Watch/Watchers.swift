//
//  Watchers.swift
//  Molten
//
//  Molten 2.0 — M4, K-P7/K-D4/K-D5/K-P10. NSMetadataQuery watchers on
//  Documents/ and Index/; synced outputs are cached locally and ingested
//  into the local SQLite store so search never depends on iCloud download
//  state. Base membership is a local path→hash mapping (renames/moves never
//  reprocess — A5). Unreferenced outputs are deleted after 7 days (K-P10).
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge.watch")

// MARK: - Local path → hash mapping (K-D5, never synced)

struct FileMapEntry: Codable, Sendable {
    let hash: String
    let base: String
    let name: String
    let mtime: TimeInterval
}

actor FileMapping {
    static let shared = FileMapping()

    private var entries: [String: FileMapEntry] = [:]
    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Molten", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("filemap.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: FileMapEntry].self, from: data) {
            entries = decoded
        }
    }

    func entry(forPath path: String) -> FileMapEntry? { entries[path] }
    func all() -> [String: FileMapEntry] { entries }

    func update(path: String, entry: FileMapEntry) {
        entries[path] = entry
        persist()
    }

    func remove(path: String) {
        entries.removeValue(forKey: path)
        persist()
    }

    func referencedHashes() -> Set<String> {
        Set(entries.values.map(\.hash))
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Documents watcher

final class DocumentWatcher: NSObject, @unchecked Sendable {
    private let query = NSMetadataQuery()
    private var onChange: (@Sendable () async -> Void)?

    func start(onChange: @escaping @Sendable () async -> Void) {
        self.onChange = onChange
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryUpdated),
            name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryUpdated),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
    }

    func stop() {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func queryUpdated() {
        Task { await onChange?() }
    }
}

// MARK: - Index watcher + local cache ingest (K-D4)

final class IndexWatcher: NSObject, @unchecked Sendable {
    private let query = NSMetadataQuery()
    private let store: KnowledgeStore
    /// Outputs are write-once and content-hash named, so a name seen once
    /// never needs re-ingesting — every metadata update used to re-read
    /// and DELETE+re-INSERT every synced file (review 2026-11-24).
    private let ingestedLock = NSLock()
    private var ingestedNames: Set<String> = []

    init(store: KnowledgeStore = .shared) {
        self.store = store
    }

    static var cacheRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Molten/IndexCache", isDirectory: true)
    }

    func start() {
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "(%K LIKE '*.mkt') OR (%K LIKE '*.mkv')",
                                      NSMetadataItemFSNameKey, NSMetadataItemFSNameKey)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryUpdated),
            name: .NSMetadataQueryDidUpdate, object: query)
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryUpdated),
            name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
    }

    func stop() {
        query.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func queryUpdated() {
        // NSMetadataQuery is bound to the run loop that started it (main —
        // KnowledgeSync.start is @MainActor) and is not thread-safe. Snapshot
        // the results on the main actor, then do the file/DB work off-main
        // (review 2026-11-24: this used to read the query from the
        // cooperative pool, racing its main-run-loop mutations).
        Task { @MainActor in
            let urls = self.snapshotResults()
            await self.ingestNewOutputs(urls)
        }
    }

    @MainActor
    private func snapshotResults() -> [URL] {
        query.disableUpdates()
        defer { query.enableUpdates() }
        var urls: [URL] = []
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem,
               let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL {
                urls.append(url)
            }
        }
        return urls
    }

    /// Copy synced outputs into the local cache and ingest them. A2: the
    /// iPhone does zero extraction/embedding — it only reads finished files.
    private func markIngested(_ key: String) {
        ingestedLock.lock()
        ingestedNames.insert(key)
        ingestedLock.unlock()
    }

    func ingestNewOutputs(_ urls: [URL]) async {
        let manifest = ManifestStore.loadOrCreate()
        for url in urls {
            // Key by full path: profile directories can hold same-named
            // outputs for different embedding profiles.
            ingestedLock.lock()
            let seen = ingestedNames.contains(url.path)
            ingestedLock.unlock()
            if seen { continue }
            if CoordinatedIO.isPlaceholderOrConflict(url) { continue }
            CoordinatedIO.downloadIfNeeded(url)
            guard let data = CoordinatedIO.read(url) else { continue }

            let cached = Self.cacheRoot.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: cached.path) {
                try? FileManager.default.createDirectory(at: Self.cacheRoot, withIntermediateDirectories: true)
                try? data.write(to: cached, options: .atomic)
            }
            do {
                if url.pathExtension == "mkt" {
                    let document = try MKTCodec.decode(data)
                    // Base membership comes from the local mapping (K-D5).
                    let mapping = await FileMapping.shared.all()
                    if let entry = mapping.values.first(where: { $0.hash == document.sourceHash }) {
                        try await store.ingest(mkt: cached, base: entry.base, name: entry.name)
                        markIngested(url.path)
                    }
                    // No mapping entry yet: leave unmarked so a later
                    // update retries once the source is mapped.
                } else if url.pathExtension == "mkv" {
                    let (header, _) = try MKVCodec.decode(data)
                    // K-E2/A6: never mix profiles or revisions.
                    guard ManifestStore.accepts(header: header, manifest: manifest) else {
                        markIngested(url.path) // permanent for this profile
                        continue
                    }
                    try await store.ingest(mkv: cached)
                    markIngested(url.path)
                }
            } catch {
                logger.error("Index ingest failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Sync coordinator (M4)

@MainActor
final class KnowledgeSync {
    static let shared = KnowledgeSync()

    private let documentWatcher = DocumentWatcher()
    private let indexWatcher = IndexWatcher()
    private var started = false

    /// Start watchers only when the shared iCloud root is active (Plus).
    func start() {
        guard !started else { return }
        guard KnowledgeContainer.activeRoot() != KnowledgeContainer.localRoot() else { return }
        started = true
        documentWatcher.start {
            await Self.refreshMapping()
            await KnowledgeCleanup.run()
        }
        indexWatcher.start()
        Task { await Self.refreshMapping() }
    }

    /// Stop watchers (Plus lapse). Nothing is deleted — existing knowledge
    /// stays searchable on each device (T6).
    func stop() {
        guard started else { return }
        documentWatcher.stop()
        indexWatcher.stop()
        started = false
    }

    /// G2/G4 (review 2026-11-24): react to a mid-session tier change.
    /// Upgrade: resolve the iCloud root, migrate local bases, start sync.
    /// Downgrade: stop sync and fall back to the local root. Previously
    /// this only happened at launch, so a Plus bought mid-session left
    /// iCloud Knowledge inert until relaunch.
    func refreshForEntitlementChange() async {
        let plus = await EntitlementManager.shared.allows(.iCloudKnowledge)
        if plus {
            await KnowledgeContainer.resolveRoot()
            try? await KnowledgeContainer.migrateLocalToICloud()
            start()
        } else {
            stop()
            await KnowledgeContainer.resolveRoot()
        }
    }

    /// K-D5: local path→hash mapping. Renames/moves only update the mapping;
    /// content-hash outputs are never regenerated (A5).
    /// nonisolated: directory enumeration, per-file resource values, and
    /// SHA-256 of changed files must not run on the main actor
    /// (review 2026-11-24: this stalled the UI on every watcher update).
    nonisolated static func refreshMapping() async {
        let fm = FileManager.default
        let documents = KnowledgeContainer.documentsRoot()
        guard let bases = try? fm.contentsOfDirectory(at: documents, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for baseDir in bases {
            guard (try? baseDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let base = baseDir.lastPathComponent
            guard let files = fm.enumerator(at: baseDir, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]) else { continue }
            for case let file as URL in files {
                let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard values?.isRegularFile == true else { continue }
                if CoordinatedIO.isPlaceholderOrConflict(file) { continue }
                let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let path = file.path
                if let existing = await FileMapping.shared.entry(forPath: path), existing.mtime == mtime {
                    continue
                }
                CoordinatedIO.downloadIfNeeded(file)
                guard CoordinatedIO.isDownloaded(file),
                      let hash = try? KnowledgeIndexer.sha256(of: file) else { continue }
                await FileMapping.shared.update(path: path, entry: FileMapEntry(
                    hash: hash, base: base, name: file.lastPathComponent, mtime: mtime))
                // Ingest already-finished outputs; on Mac, process new files.
                let mkt = KnowledgeContainer.textDirectory().appendingPathComponent("\(hash).mkt")
                if fm.fileExists(atPath: mkt.path) {
                    try? await KnowledgeStore.shared.ingest(mkt: mkt, base: base, name: file.lastPathComponent)
                } else {
                    try? await KnowledgeIndexer.shared.process(file: file, base: base)
                }
            }
        }
        // Drop mapping entries and index rows for files deleted on this or
        // another device (see pruneMapping for the collision/K-D5 rules).
        await pruneMapping(mapping: .shared, store: .shared)
    }

    /// Prune mapping entries whose files vanished (here or on another
    /// device) and drop their index rows. Evicted iCloud files still exist
    /// as ".name.icloud" placeholders — keep those entries.
    ///
    /// The base+name row goes only when no remaining mapping entry shares
    /// it: two live files can share one base+name (same filename in
    /// different subfolders), and deleting one must not drop the survivor's
    /// row — the survivor is never re-ingested (mtime-unchanged skip), so
    /// the loss would be permanent. When the last path for a base+name
    /// goes, the row still goes unconditionally, preserving the K-D5
    /// stale-count fix (review 2026-11-24).
    nonisolated static func pruneMapping(
        mapping: FileMapping,
        store: KnowledgeStore,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) async {
        let entries = await mapping.all()
        for (path, entry) in entries {
            if fileExists(path) { continue }
            let url = URL(fileURLWithPath: path)
            let placeholder = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).icloud")
            if fileExists(placeholder.path) { continue }
            await mapping.remove(path: path)
            let remaining = await mapping.all()
            let nameStillReferenced = remaining.values.contains {
                $0.base == entry.base && $0.name == entry.name
            }
            if !nameStillReferenced {
                await store.removeDocument(base: entry.base, name: entry.name)
            }
            let stillReferenced = await mapping.referencedHashes().contains(entry.hash)
            if !stillReferenced {
                await store.removeDocument(hash: entry.hash)
            }
        }
    }
}

// MARK: - Cleanup (K-P10)

enum KnowledgeCleanup {
    static let graceDays = 7

    /// Delete outputs no document references, older than the grace window.
    static func run() async {
        let mapping = await FileMapping.shared.all()
        let referenced = Set(mapping.values.map(\.hash))
        let fm = FileManager.default
        // Safety: the mapping only covers files this device has downloaded
        // and hashed. If any source document is missing from it (cloud-only
        // placeholders, a scan still in progress), "unreferenced" is not
        // trustworthy — pruning would delete shared outputs that other
        // devices still need. Skip cleanup until the mapping is complete.
        let documents = KnowledgeContainer.documentsRoot()
        if let enumerator = fm.enumerator(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []) {
            for case let file as URL in enumerator {
                // Evicted iCloud documents appear as hidden ".name.icloud"
                // placeholders and are never mapped — keep their outputs.
                if file.lastPathComponent.hasSuffix(".icloud") { return }
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                if CoordinatedIO.isPlaceholderOrConflict(file) { continue }
                if mapping[file.path] == nil { return }
            }
        }
        let cutoff = Date().addingTimeInterval(-Double(graceDays) * 86400)
        for dir in [KnowledgeContainer.textDirectory(),
                    KnowledgeContainer.vectorsDirectory(profile: EmbeddingProfile.e5sV1.id)] {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for file in files {
                let hash = file.deletingPathExtension().lastPathComponent
                if referenced.contains(hash) { continue }
                let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                if mtime < cutoff {
                    try? fm.removeItem(at: file)
                    logger.info("Cleaned unreferenced output \(file.lastPathComponent, privacy: .public)")
                }
            }
        }
    }
}

//
//  Watchers.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-P7 stubs. M4: NSMetadataQuery on Documents/ (ubiquitous documents scope).
final class DocumentWatcher: Sendable {
    func start() { /* M4 */ }
    func stop() { /* M4 */ }
}

/// K-P7 stub. M4: NSMetadataQuery on Index/ (ubiquitous data scope) feeding
/// new .mkt/.mkv files into the local KnowledgeStore.
final class IndexWatcher: Sendable {
    func start() { /* M4 */ }
    func stop() { /* M4 */ }
}

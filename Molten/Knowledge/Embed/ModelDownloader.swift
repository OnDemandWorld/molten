//
//  ModelDownloader.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-E3 stub. M1: MLX Hugging Face downloader at the pinned revision, hash
/// verification, Application Support/Molten/Models/ (excluded from backup),
/// size shown before download, cellular confirmation on iOS.
actor ModelDownloader {
    func download(profile: EmbeddingProfile, progress: @Sendable (Double) -> Void) async throws {
        throw KnowledgeError.notImplemented("ModelDownloader — M1")
    }
}

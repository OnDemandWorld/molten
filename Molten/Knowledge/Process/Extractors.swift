//
//  Extractors.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// K-P8 stub. M3: PDFKit, UTF-8 text/code, NSAttributedString (RTF/HTML),
/// built-in DOCX reader; Vision OCR (Plus) for scanned pages/images.
struct ExtractedDocument: Sendable {
    var text: String
    var pages: [PageRange]
    var ocrUsed: Bool
    struct PageRange: Sendable { var index: Int; var charStart: Int; var charEnd: Int }
}

protocol Extractor: Sendable {
    func extract(from url: URL) async throws -> ExtractedDocument
}

//
//  Extractors.swift
//  Molten
//
//  Molten 2.0 — M3, K-P8. PDFKit for PDFs; Vision OCR (Plus only) for pages
//  with <50 extractable characters and for PNG/JPEG/HEIC; UTF-8 for text,
//  Markdown and source code; NSAttributedString for RTF/HTML; built-in DOCX
//  reader (unzip word/document.xml). Unsupported files throw.
//

import Foundation
import PDFKit
import Vision
import Compression
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ExtractedDocument: Sendable {
    var text: String
    var pages: [MKTPage]
    var ocrUsed: Bool
}

enum ExtractionError: Error {
    case unsupported(String)
    case unreadable(String)
}

protocol Extractor: Sendable {
    func extract(from url: URL) async throws -> ExtractedDocument
}

enum ExtractorFactory {
    static let codeExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx", "json", "yaml", "yml", "csv",
        "c", "h", "cpp", "hpp", "rs", "go", "rb", "sh", "java", "kt", "m", "mm",
        "txt", "md", "markdown", "text", "log", "xml", "toml", "ini",
    ]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic"]

    static func extractor(for url: URL, ocrAllowed: Bool) -> Extractor? {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return PDFExtractor(ocrAllowed: ocrAllowed)
        case "rtf", "rtfd", "html", "htm":
            return RichTextExtractor()
        case "docx":
            return DOCXExtractor()
        case let ext where imageExtensions.contains(ext):
            return ocrAllowed ? ImageOCRExtractor() : nil
        case let ext where codeExtensions.contains(ext):
            return PlainTextExtractor()
        default:
            return nil
        }
    }
}

// MARK: - Plain text / code

struct PlainTextExtractor: Extractor {
    func extract(from url: URL) async throws -> ExtractedDocument {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ExtractionError.unreadable(url.lastPathComponent)
        }
        let length = (text as NSString).length
        return ExtractedDocument(
            text: text,
            pages: length > 0 ? [MKTPage(index: 1, charStart: 0, charEnd: length)] : [],
            ocrUsed: false)
    }
}

// MARK: - PDF (+ OCR for scanned pages, Plus only)

struct PDFExtractor: Extractor {
    let ocrAllowed: Bool
    static let ocrThreshold = 50 // K-P8

    func extract(from url: URL) async throws -> ExtractedDocument {
        guard let document = PDFDocument(url: url) else {
            throw ExtractionError.unreadable(url.lastPathComponent)
        }
        var full = ""
        var pages: [MKTPage] = []
        var ocrUsed = false
        // Running UTF-16 offset: (full as NSString).length per page is O(n)
        // on native Swift strings, making the loop O(n²) on long documents.
        var offset = 0
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            var pageText = page.string ?? ""
            if pageText.trimmingCharacters(in: .whitespacesAndNewlines).count < Self.ocrThreshold,
               ocrAllowed,
               let image = page.thumbnail(of: CGSize(width: 1700, height: 2200), for: .mediaBox).cgImageCompat {
                let recognized = (try? await ImageOCRExtractor.recognizeText(in: image)) ?? ""
                if !recognized.isEmpty {
                    pageText = recognized
                    ocrUsed = true
                }
            }
            let start = offset
            if !full.isEmpty { full += "\n\n"; offset += 2 }
            full += pageText
            offset += (pageText as NSString).length
            pages.append(MKTPage(index: i + 1, charStart: start, charEnd: offset))
        }
        return ExtractedDocument(text: full, pages: pages, ocrUsed: ocrUsed)
    }
}

// MARK: - RTF / HTML

struct RichTextExtractor: Extractor {
    func extract(from url: URL) async throws -> ExtractedDocument {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] =
            url.pathExtension.lowercased().hasPrefix("htm")
            ? [.documentType: NSAttributedString.DocumentType.html]
            : [.documentType: NSAttributedString.DocumentType.rtf]
        guard let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else {
            throw ExtractionError.unreadable(url.lastPathComponent)
        }
        let text = attributed.string
        let length = (text as NSString).length
        return ExtractedDocument(
            text: text,
            pages: length > 0 ? [MKTPage(index: 1, charStart: 0, charEnd: length)] : [],
            ocrUsed: false)
    }
}

// MARK: - DOCX (built-in reader: unzip word/document.xml)

struct DOCXExtractor: Extractor {
    func extract(from url: URL) async throws -> ExtractedDocument {
        guard let xml = try MiniZip.fileData(named: "word/document.xml", in: url) else {
            throw ExtractionError.unreadable(url.lastPathComponent)
        }
        var text = String(decoding: xml, as: UTF8.self)
        // Paragraph and break boundaries become newlines, then strip tags.
        text = text.replacingOccurrences(of: "</w:p>", with: "\n")
        text = text.replacingOccurrences(of: "<w:br[^>]*/>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<w:tab[^>]*/>", with: "\t", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        if let decoded = try? NSAttributedString(
            data: Data(text.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil) {
            text = decoded.string
        }
        let length = (text as NSString).length
        return ExtractedDocument(
            text: text,
            pages: length > 0 ? [MKTPage(index: 1, charStart: 0, charEnd: length)] : [],
            ocrUsed: false)
    }
}

// MARK: - Image OCR (Plus only — gated by the factory)

struct ImageOCRExtractor: Extractor {
    func extract(from url: URL) async throws -> ExtractedDocument {
        guard let image = PlatformImage(contentsOfFile: url.path)?.cgImageCompat else {
            throw ExtractionError.unreadable(url.lastPathComponent)
        }
        let text = try await Self.recognizeText(in: image)
        let length = (text as NSString).length
        return ExtractedDocument(
            text: text,
            pages: length > 0 ? [MKTPage(index: 1, charStart: 0, charEnd: length)] : [],
            ocrUsed: true)
    }

    static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Minimal ZIP reader (stored + deflate entries)

enum MiniZip {
    static func fileData(named name: String, in archive: URL) throws -> Data? {
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        var offset = 0
        while offset + 30 <= data.count {
            guard le32(data, offset) == 0x04034b50 else { break }
            let method = le16(data, offset + 8)
            var compSize = Int(le32(data, offset + 18))
            let nameLen = Int(le16(data, offset + 26))
            let extraLen = Int(le16(data, offset + 28))
            let nameStart = offset + 30
            guard nameStart + nameLen <= data.count else { break }
            let fileName = String(decoding: data.subdata(in: nameStart..<nameStart + nameLen), as: UTF8.self)
            let bodyStart = nameStart + nameLen + extraLen
            if fileName == name {
                if compSize == 0 {
                    // Data-descriptor archives: find the next header boundary.
                    if let next = nextHeaderOffset(data, from: bodyStart) {
                        compSize = next - bodyStart
                    } else {
                        compSize = data.count - bodyStart
                    }
                }
                guard bodyStart + compSize <= data.count else { return nil }
                let body = data.subdata(in: bodyStart..<bodyStart + compSize)
                if method == 0 { return body }
                if method == 8 { return inflateRawDeflate(body) }
                return nil
            }
            offset = bodyStart + compSize
        }
        return nil
    }

    private static func nextHeaderOffset(_ data: Data, from: Int) -> Int? {
        var i = from
        while i + 4 <= data.count {
            let sig = le32(data, i)
            if sig == 0x04034b50 || sig == 0x02014b50 || sig == 0x06054b50 { return i }
            i += 1
        }
        return nil
    }

    private static func le16(_ data: Data, _ at: Int) -> UInt16 {
        data.subdata(in: at..<at + 2).withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self)) }
    }
    private static func le32(_ data: Data, _ at: Int) -> UInt32 {
        data.subdata(in: at..<at + 4).withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }
}

func inflateRawDeflate(_ input: Data) -> Data? {
    var capacity = max(input.count * 4, 65536)
    for _ in 0..<10 {
        var output = Data(count: capacity)
        let written = input.withUnsafeBytes { src in
            output.withUnsafeMutableBytes { dst in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        if written == 0 { return nil }
        if written < capacity { return output.prefix(written) }
        capacity *= 4
    }
    return nil
}

// MARK: - Use once in this chat (K-U4, Free)

enum UseOnce {
    /// Extracts a document's text for one-shot injection into the prompt.
    /// Not indexed. Truncated to the token budget (X2).
    static func extractText(from url: URL, budgetTokens: Int = 6000) async -> String? {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        guard let extractor = ExtractorFactory.extractor(for: url, ocrAllowed: false),
              let document = try? await extractor.extract(from: url) else { return nil }
        var text = document.text
        while TokenEstimator.estimate(text) > budgetTokens && text.count > 1000 {
            text = String(text.prefix(text.count * 3 / 4))
        }
        return text
    }
}

// MARK: - Platform image helpers

extension PlatformImage {
    var cgImageCompat: CGImage? {
        #if os(macOS)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return cgImage
        #endif
    }
}

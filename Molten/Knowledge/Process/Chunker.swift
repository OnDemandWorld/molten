//
//  Chunker.swift
//  Molten
//
//  Molten 2.0 — M3, K-P9. ~350-token chunks with ~50-token overlap,
//  splitting at headings/paragraphs first, hard cap 480 tokens including
//  the passage prefix. Page and character ranges recorded (UTF-16 offsets,
//  matching PDFKit/Quick Look). Token counts use the e5 tokenizer (K-E6)
//  via the injected counter.
//

import Foundation

enum Chunker {
    static let chunkerVersion = 1
    static let targetTokens = 350
    static let overlapTokens = 50
    static let maxTokens = 480

    /// A source segment with its UTF-16 range in the original text.
    struct Segment {
        let text: String
        let start: Int
        let end: Int
    }

    static func chunk(
        text: String,
        pages: [MKTPage],
        prefix: String,
        tokenCount: (String) async -> Int
    ) async -> [MKTChunk] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let ns = text as NSString
        var chunks: [MKTChunk] = []
        var current: [Segment] = []
        var currentTokens = 0
        var overlap: [Segment] = []

        func flush() async {
            guard !current.isEmpty else { return }
            let start = current.first!.start
            let end = current.last!.end
            let body = ns.substring(with: NSRange(location: start, length: end - start))
            let tokens = await tokenCount(prefix + body)
            chunks.append(MKTChunk(
                i: chunks.count,
                text: body,
                page: page(for: start, pages: pages),
                charStart: start,
                charEnd: end,
                tokens: tokens))
            // Carry ~overlapTokens of trailing text into the next chunk.
            overlap = await trailingSegments(current, budget: overlapTokens, tokenCount: tokenCount)
            current = []
            currentTokens = 0
        }

        for block in blocks(of: text) {
            let blockTokens = await tokenCount(prefix + block.text)
            if blockTokens > maxTokens {
                // Oversized block: flush, then split by sentences/words.
                await flush()
                for piece in await splitOversized(block, prefix: prefix, tokenCount: tokenCount) {
                    let tokens = await tokenCount(prefix + piece.text)
                    chunks.append(MKTChunk(
                        i: chunks.count,
                        text: piece.text,
                        page: page(for: piece.start, pages: pages),
                        charStart: piece.start,
                        charEnd: piece.end,
                        tokens: tokens))
                }
                overlap = []
                continue
            }
            if currentTokens + blockTokens > targetTokens && !current.isEmpty {
                await flush()
                current = overlap
                currentTokens = await tokenCount(prefix + current.map(\.text).joined())
            }
            current.append(block)
            currentTokens += blockTokens
            // Overlap + block can exceed the hard cap: keep only the block
            // (itself verified ≤ maxTokens above) — review 2026-11-24.
            if currentTokens > maxTokens {
                current = [block]
                currentTokens = blockTokens
            }
        }
        await flush()
        return chunks
    }

    // MARK: - Segmentation

    /// Paragraphs, keeping headings attached to their following paragraph.
    static func blocks(of text: String) -> [Segment] {
        let ns = text as NSString
        var segments: [Segment] = []
        var location = 0
        let full = NSRange(location: 0, length: ns.length)
        ns.enumerateSubstrings(in: full, options: [.byParagraphs, .substringNotRequired]) { _, range, _, _ in
            let piece = ns.substring(with: range)
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            // Tighten to non-whitespace content.
            let lead = piece.count - piece.drop(while: { $0.isWhitespace || $0.isNewline }).count
            let start = range.location + lead
            let end = range.location + range.length
            let content = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            let contentStart = start + (ns.substring(with: NSRange(location: start, length: end - start))
                .count - ns.substring(with: NSRange(location: start, length: end - start))
                .drop(while: { $0.isWhitespace || $0.isNewline }).count)
            segments.append(Segment(text: content, start: contentStart, end: contentStart + (content as NSString).length))
            location = range.location + range.length
        }
        _ = location
        return segments
    }

    /// Split a block that alone exceeds the hard cap: sentences first, then words.
    static func splitOversized(
        _ block: Segment,
        prefix: String,
        tokenCount: (String) async -> Int
    ) async -> [Segment] {
        var pieces: [Segment] = []
        var sentenceStarts: [Int] = []
        let ns = block.text as NSString
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            sentenceStarts.append(range.location)
        }
        sentenceStarts.append(ns.length)
        var currentStart = 0
        var currentEnd = 0
        for i in 0..<sentenceStarts.count - 1 {
            let sStart = sentenceStarts[i]
            let sEnd = sentenceStarts[i + 1]
            let candidate = ns.substring(with: NSRange(location: currentStart, length: sEnd - currentStart))
            let tokens = await tokenCount(prefix + candidate)
            if tokens > maxTokens && currentEnd > currentStart {
                pieces.append(makePiece(ns, block.start, currentStart, currentEnd))
                currentStart = sStart
            }
            currentEnd = sEnd
            // A single sentence still over the cap: split by words.
            if await tokenCount(prefix + ns.substring(with: NSRange(location: currentStart, length: currentEnd - currentStart))) > maxTokens {
                pieces.append(contentsOf: await splitByWords(ns, base: block.start, from: currentStart, to: currentEnd, prefix: prefix, tokenCount: tokenCount))
                currentStart = currentEnd
            }
        }
        if currentEnd > currentStart {
            pieces.append(makePiece(ns, block.start, currentStart, currentEnd))
        }
        return pieces
    }

    static func splitByWords(
        _ ns: NSString,
        base: Int,
        from: Int,
        to: Int,
        prefix: String,
        tokenCount: (String) async -> Int
    ) async -> [Segment] {
        var pieces: [Segment] = []
        var start = from
        var end = from
        let range = NSRange(location: from, length: to - from)
        var wordEnds: [Int] = []
        ns.enumerateSubstrings(in: range, options: [.byWords, .substringNotRequired]) { _, r, _, _ in
            wordEnds.append(r.location + r.length)
        }
        wordEnds.append(to)
        for wEnd in wordEnds {
            let candidate = ns.substring(with: NSRange(location: start, length: wEnd - start))
            if await tokenCount(prefix + candidate) > maxTokens && end > start {
                pieces.append(contentsOf: await hardSplit(ns, base: base, from: start, to: end, prefix: prefix, tokenCount: tokenCount))
                start = end
            }
            end = wEnd
        }
        if end > start {
            pieces.append(contentsOf: await hardSplit(ns, base: base, from: start, to: end, prefix: prefix, tokenCount: tokenCount))
        }
        return pieces
    }

    /// Character-bisection fallback for a single unbroken run (long URL,
    /// base64, CJK without spaces) that exceeds the cap on its own —
    /// splitByWords used to emit it as one oversized chunk (review
    /// 2026-11-24). Returns the piece unchanged when it already fits.
    static func hardSplit(
        _ ns: NSString,
        base: Int,
        from: Int,
        to: Int,
        prefix: String,
        tokenCount: (String) async -> Int
    ) async -> [Segment] {
        let text = ns.substring(with: NSRange(location: from, length: to - from))
        let fits = await tokenCount(prefix + text) <= maxTokens
        if to - from <= 1 || fits {
            let piece = makePiece(ns, base, from, to)
            return piece.text.isEmpty ? [] : [piece]
        }
        let mid = from + (to - from) / 2
        var out = await hardSplit(ns, base: base, from: from, to: mid, prefix: prefix, tokenCount: tokenCount)
        let tail = await hardSplit(ns, base: base, from: mid, to: to, prefix: prefix, tokenCount: tokenCount)
        out += tail
        return out
    }

    static func makePiece(_ ns: NSString, _ base: Int, _ start: Int, _ end: Int) -> Segment {
        let text = ns.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Segment(text: text, start: base + start, end: base + end)
    }

    static func trailingSegments(
        _ segments: [Segment],
        budget: Int,
        tokenCount: (String) async -> Int
    ) async -> [Segment] {
        var result: [Segment] = []
        var tokens = 0
        for segment in segments.reversed() {
            let t = await tokenCount(segment.text)
            // Never exceed the budget, even for a single oversized trailing
            // segment — it used to become the entire overlap and blow the
            // hard cap (review 2026-11-24). Empty overlap is acceptable.
            if tokens + t > budget { break }
            result.insert(segment, at: 0)
            tokens += t
            if tokens >= budget { break }
        }
        return result
    }

    static func page(for location: Int, pages: [MKTPage]) -> Int? {
        pages.first { location >= $0.charStart && location < $0.charEnd }?.index
    }
}

//
//  ContextBudget.swift
//  Molten
//
//  Molten 2.0 — X2 (used by K-R4 and K-U4 from M3; meter UI in M6).
//  Divides the context window between system prompt, Knowledge chunks,
//  history (newest first) and a reply reserve: min(1024, 25% of window).
//

import Foundation

struct ContextBudget: Sendable {
    struct Allocation: Sendable {
        var chunks: [Passage]
        var history: [ChatMessage]
        var usedTokens: Int
        var window: Int
        var reserve: Int
    }

    static func defaultReserve(window: Int) -> Int {
        min(1024, window / 4)
    }

    func allocate(
        window: Int,
        system: Int,
        reserve: Int,
        chunks: [Passage],
        history: [ChatMessage]
    ) -> Allocation {
        var remaining = max(0, window - system - reserve)
        var used = system

        var selectedChunks: [Passage] = []
        for chunk in chunks {
            let cost = TokenEstimator.estimate(chunk.text)
            guard cost <= remaining else { break }
            selectedChunks.append(chunk)
            remaining -= cost
            used += cost
        }

        var selectedHistory: [ChatMessage] = []
        for (index, message) in history.reversed().enumerated() { // newest first
            let cost = TokenEstimator.estimate(message.content?.textContent ?? "")
            if cost <= remaining {
                selectedHistory.insert(message, at: 0)
                remaining -= cost
                used += cost
            } else if index == 0 {
                // The newest message is the prompt being answered — never
                // drop it, even when it alone exceeds the remaining budget.
                selectedHistory.insert(message, at: 0)
                used += cost
                remaining = 0
            }
            // Older messages that don't fit are skipped, not fatal: smaller
            // older messages may still fit.
        }

        return Allocation(
            chunks: selectedChunks,
            history: selectedHistory,
            usedTokens: used,
            window: window,
            reserve: reserve)
    }
}

extension ContentType {
    var textContent: String? {
        switch self {
        case .string(let text): return text
        case .array(let parts): return parts.compactMap(\.text).joined(separator: " ")
        }
    }
}

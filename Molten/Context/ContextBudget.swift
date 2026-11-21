//
//  ContextBudget.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// X2 stub. M6: shared allocator dividing the window between system prompt,
/// Knowledge chunks, history (newest first) and reply reserve
/// (min(1024, 25% of window)). Used by K-R4, K-U4 and normal chat.
struct ContextBudget: Sendable {
    struct Allocation: Sendable {
        var chunks: [Passage]
        var history: [ChatMessage]
        var usedTokens: Int
    }

    func allocate(window: Int, system: Int, reserve: Int,
                  chunks: [Passage], history: [ChatMessage]) -> Allocation {
        Allocation(chunks: [], history: [], usedTokens: 0) // M6
    }
}

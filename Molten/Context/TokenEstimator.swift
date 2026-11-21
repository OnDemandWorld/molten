//
//  TokenEstimator.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// X1 support. Matches the existing analytics estimate convention
/// (~4 characters per token) until a tokenizer-backed estimate lands.
enum TokenEstimator {
    static func estimate(_ text: String) -> Int {
        max(1, text.count / 4)
    }
}

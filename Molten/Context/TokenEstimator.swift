//
//  TokenEstimator.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// X1 support. Matches the existing analytics estimate convention
/// (~4 characters per token) for Latin text. CJK characters are roughly
/// one token each — plain chars/4 undercounts them ~4x, which let
/// pre-download chunks exceed the embedding model's 512-token window
/// (review 2026-11-24).
enum TokenEstimator {
    static func estimate(_ text: String) -> Int {
        var cjk = 0
        var other = 0
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0x3400...0x4DBF,   // CJK Extension A
                 0x3040...0x30FF,   // Hiragana + Katakana
                 0xAC00...0xD7AF,   // Hangul syllables
                 0xF900...0xFAFF:   // CJK Compatibility Ideographs
                cjk += 1
            default:
                other += 1
            }
        }
        return max(1, cjk + other / 4)
    }
}

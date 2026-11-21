//
//  Codecs.swift
//  Molten
//
//  Molten 2.0 — M0 skeleton stub (PRD §7.1/§7.2). Inert until its milestone.
//

import Foundation

/// §7.3 stubs. M3: .mkt = MKT1 magic + LZFSE-compressed UTF-8 JSON;
/// .mkv = MKV1 magic + uint32 header length + JSON header + Float16 vectors
/// in .mkt chunk order. Both carry a reserved `encryption` field (P5).
enum MKTCodec {
    static let magic = "MKT1"
}

enum MKVCodec {
    static let magic = "MKV1"
}

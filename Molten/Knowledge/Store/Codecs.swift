//
//  Codecs.swift
//  Molten
//
//  Molten 2.0 — M3. Content-addressed index file formats (PRD §7.3).
//  .mkt: MKT1 magic + LZFSE-compressed UTF-8 JSON (text + chunks,
//        model-independent, produced once per document — K-D1).
//  .mkv: MKV1 magic + uint32 header length + JSON header + Float16 vectors
//        in .mkt chunk order, one embedding profile per file (K-D2).
//  Files are written once and never edited (K-D3). `encryption` is reserved
//  for P5 (2.1) and must be null in 2.0.
//

import Foundation
import Compression

// MARK: - MKT

struct MKTPage: Codable, Sendable, Equatable {
    let index: Int
    let charStart: Int
    let charEnd: Int
}

struct MKTChunk: Codable, Sendable, Equatable {
    let i: Int
    let text: String
    let page: Int?
    let charStart: Int
    let charEnd: Int
    let tokens: Int
}

struct MKTDocument: Codable, Sendable, Equatable {
    let schema: Int
    let sourceHash: String
    let mime: String
    let extractorVersion: Int
    let ocrUsed: Bool
    let chunkerVersion: Int
    let pages: [MKTPage]
    let chunks: [MKTChunk]
    let encryption: String?
    let createdBy: String
    let createdAt: String

    static let currentSchema = 1
    static let extractorVersion = 1
}

enum MKTCodec {
    static let magic = Data("MKT1".utf8)

    static func encode(_ document: MKTDocument) throws -> Data {
        let json = try JSONEncoder().encode(document)
        guard let compressed = compressLZFSE(json) else {
            throw KnowledgeError.notImplemented("MKT compression failed")
        }
        return magic + compressed
    }

    static func decode(_ data: Data) throws -> MKTDocument {
        guard data.count > 4, data.prefix(4) == magic else {
            throw KnowledgeError.notImplemented("Bad MKT magic")
        }
        guard let json = decompressLZFSE(data.dropFirst(4)) else {
            throw KnowledgeError.notImplemented("MKT decompression failed")
        }
        return try JSONDecoder().decode(MKTDocument.self, from: json)
    }
}

// MARK: - MKV

struct MKVHeader: Codable, Sendable, Equatable {
    let schema: Int
    let sourceHash: String
    let profileID: String
    let modelRevision: String
    let dims: Int
    let count: Int
    let chunkerVersion: Int
    let encryption: String?
    let createdBy: String
    let createdAt: String
}

enum MKVCodec {
    static let magic = Data("MKV1".utf8)

    static func encode(header: MKVHeader, vectors: [[Float]]) throws -> Data {
        guard vectors.count == header.count,
              vectors.allSatisfy({ $0.count == header.dims }) else {
            throw KnowledgeError.notImplemented("MKV shape mismatch")
        }
        let headerJSON = try JSONEncoder().encode(header)
        var out = magic
        var length = UInt32(headerJSON.count).littleEndian
        withUnsafeBytes(of: &length) { out.append(contentsOf: $0) }
        out.append(headerJSON)
        for vector in vectors {
            for value in vector {
                var bits = HalfFloat.bits(from: value).littleEndian
                withUnsafeBytes(of: &bits) { out.append(contentsOf: $0) }
            }
        }
        return out
    }

    static func decode(_ data: Data) throws -> (header: MKVHeader, vectors: [[Float]]) {
        guard data.count > 8, data.prefix(4) == magic else {
            throw KnowledgeError.notImplemented("Bad MKV magic")
        }
        let headerLength = data.subdata(in: 4..<8).withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
        }
        let headerEnd = 8 + Int(headerLength)
        guard data.count >= headerEnd else {
            throw KnowledgeError.notImplemented("Truncated MKV header")
        }
        let header = try JSONDecoder().decode(MKVHeader.self, from: data.subdata(in: 8..<headerEnd))
        let payload = data.dropFirst(headerEnd)
        let expected = header.count * header.dims * 2
        guard payload.count == expected else {
            throw KnowledgeError.notImplemented("MKV payload size mismatch")
        }
        var vectors: [[Float]] = []
        vectors.reserveCapacity(header.count)
        var offset = payload.startIndex
        for _ in 0..<header.count {
            var vector: [Float] = []
            vector.reserveCapacity(header.dims)
            for _ in 0..<header.dims {
                let bits = payload.subdata(in: offset..<offset + 2).withUnsafeBytes {
                    UInt16(littleEndian: $0.loadUnaligned(as: UInt16.self))
                }
                vector.append(HalfFloat.float(fromBits: bits))
                offset += 2
            }
            vectors.append(vector)
        }
        return (header, vectors)
    }
}

// MARK: - IEEE 754 binary16 (architecture-independent)

/// `Float16` is unavailable on x86_64, but Release archives build universal
/// (arm64 + x86_64). These bit-level conversions produce exactly the same
/// IEEE binary16 values as `Float16(_:)` / `Float(Float16)` on arm64
/// (round-to-nearest-even, subnormals, inf/NaN), so the .mkv on-disk format
/// is identical on every architecture and CPU.
enum HalfFloat {
    static func bits(from value: Float) -> UInt16 {
        let b = value.bitPattern
        let sign = UInt16((b >> 16) & 0x8000)
        let rawExp = (b >> 23) & 0xFF
        let mant = b & 0x7FFFFF

        // inf / NaN
        if rawExp == 0xFF {
            if mant != 0 {
                var m = UInt16(mant >> 13) | 0x200 // quiet bit, as hardware FCVT does
                if m == 0 { m = 1 } // keep NaN non-zero after truncation
                return sign | 0x7C00 | m
            }
            return sign | 0x7C00
        }

        let exp = Int32(rawExp) - 127 + 15
        if exp >= 0x1F { return sign | 0x7C00 } // overflow → inf

        if exp <= 0 {
            // Subnormal (or rounds to zero).
            if exp < -10 { return sign }
            let m = mant | 0x800000 // implicit leading 1
            let shift = UInt32(14 - exp)
            var half = m >> shift
            let rem = m & ((1 << shift) - 1)
            let halfway = UInt32(1) << (shift - 1)
            if rem > halfway || (rem == halfway && (half & 1) == 1) { half += 1 }
            return sign | UInt16(half)
        }

        var half = (UInt32(exp) << 10) | (mant >> 13)
        let rem = mant & 0x1FFF
        if rem > 0x1000 || (rem == 0x1000 && (half & 1) == 1) { half += 1 }
        return sign | UInt16(half) // carry may round up into the exponent
    }

    static func float(fromBits bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exp = UInt32(bits >> 10) & 0x1F
        let mant = UInt32(bits & 0x3FF)
        if exp == 0 {
            if mant == 0 { return Float(bitPattern: sign) }
            // Normalize the subnormal into a Float normal.
            var e = UInt32(127 - 15 + 1)
            var m = mant
            while (m & 0x400) == 0 {
                m <<= 1
                e -= 1
            }
            m &= 0x3FF
            return Float(bitPattern: sign | (e << 23) | (m << 13))
        }
        if exp == 0x1F {
            return Float(bitPattern: sign | 0x7F800000 | (mant << 13))
        }
        return Float(bitPattern: sign | ((exp + 127 - 15) << 23) | (mant << 13))
    }
}

// MARK: - LZFSE (Apple Compression framework)

func compressLZFSE(_ input: Data) -> Data? {
    guard !input.isEmpty else { return Data() }
    let capacity = input.count + 4096
    var output = Data(count: capacity)
    let written = input.withUnsafeBytes { src in
        output.withUnsafeMutableBytes { dst in
            compression_encode_buffer(
                dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                nil, COMPRESSION_LZFSE)
        }
    }
    guard written > 0 else { return nil }
    return output.prefix(written)
}

func decompressLZFSE(_ input: Data) -> Data? {
    if input.isEmpty { return Data() }
    // Grow until the whole stream fits (decoded size is not stored).
    var capacity = max(input.count * 4, 65536)
    for _ in 0..<8 {
        var output = Data(count: capacity)
        let written = input.withUnsafeBytes { src in
            output.withUnsafeMutableBytes { dst in
                compression_decode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_LZFSE)
            }
        }
        if written == 0 { return nil }
        if written < capacity { return output.prefix(written) }
        capacity *= 4
    }
    return nil
}

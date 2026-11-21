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
                var bits = Float16(value).bitPattern.littleEndian
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
                vector.append(Float(Float16(bitPattern: bits)))
                offset += 2
            }
            vectors.append(vector)
        }
        return (header, vectors)
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

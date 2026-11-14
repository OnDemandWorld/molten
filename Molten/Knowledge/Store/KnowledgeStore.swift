//
//  KnowledgeStore.swift
//  Molten
//
//  Molten 2.0 — M3, K-D4. Local SQLite (FTS5 + vector table) built from
//  .mkt/.mkv files. No database is synced; each device builds its own.
//  Search never depends on iCloud download state (local index cache).
//

import Foundation
import SQLite3
import Accelerate
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "knowledge.store")

struct Passage: Sendable, Identifiable {
    let id: String
    let text: String
    let sourceName: String
    let page: Int?
    let charStart: Int
    let charEnd: Int
    var score: Double
}

enum KnowledgeError: Error {
    case notImplemented(String)
    case modelNotReady
    case store(String)
}

actor KnowledgeStore {
    static let shared = KnowledgeStore()

    private var db: OpaquePointer?
    private let dbURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Molten", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        dbURL = base.appendingPathComponent("knowledge.sqlite")
        var handle: OpaquePointer?
        guard sqlite3_open(dbURL.path, &handle) == SQLITE_OK else {
            logger.error("Failed to open knowledge store at \(self.dbURL.path, privacy: .public)")
            return
        }
        db = handle
        Self.migrate(handle)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Schema

    private nonisolated static func migrate(_ db: OpaquePointer?) {
        Self.exec(db, """
            CREATE TABLE IF NOT EXISTS bases (
                name TEXT PRIMARY KEY,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS documents (
                hash TEXT PRIMARY KEY,
                base TEXT NOT NULL,
                name TEXT NOT NULL,
                mime TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS chunks (
                hash TEXT NOT NULL,
                i INTEGER NOT NULL,
                text TEXT NOT NULL,
                page INTEGER,
                char_start INTEGER NOT NULL,
                char_end INTEGER NOT NULL,
                tokens INTEGER NOT NULL,
                PRIMARY KEY (hash, i)
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                text, content='chunks', content_rowid='rowid'
            );
            CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
                INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
            END;
            CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
            END;
            CREATE TABLE IF NOT EXISTS vectors (
                hash TEXT NOT NULL,
                i INTEGER NOT NULL,
                profile TEXT NOT NULL,
                revision TEXT NOT NULL,
                vec BLOB NOT NULL,
                PRIMARY KEY (hash, i, profile)
            );
            CREATE INDEX IF NOT EXISTS idx_documents_base ON documents(base);
            CREATE INDEX IF NOT EXISTS idx_vectors_profile ON vectors(profile, revision);
            """)
    }

    private nonisolated static func exec(_ db: OpaquePointer?, _ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown"
            logger.error("SQLite exec failed: \(message, privacy: .public)")
            sqlite3_free(error)
        }
    }

    // MARK: - Bases

    func createBase(_ name: BaseID) {
        run("INSERT OR IGNORE INTO bases(name, created_at) VALUES (?, ?)",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, ISO8601DateFormatter().string(from: Date()), -1, SQLITE_TRANSIENT)
            })
    }

    func bases() -> [BaseID] {
        var result: [BaseID] = []
        query("SELECT name FROM bases ORDER BY name") { stmt in
            result.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return result
    }

    func hasDocument(hash: String) -> Bool {
        var found = false
        query("SELECT 1 FROM documents WHERE hash = ? LIMIT 1", bind: { stmt in
            sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        }) { _ in found = true }
        return found
    }

    func documentCount(base: BaseID) -> Int {
        var count = 0
        query("SELECT COUNT(*) FROM documents WHERE base = ?", bind: { stmt in
            sqlite3_bind_text(stmt, 1, base, -1, SQLITE_TRANSIENT)
        }) { stmt in
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    /// K-U1: vector coverage for the status vocabulary.
    func vectorCount(base: BaseID) -> Int {
        var count = 0
        query("""
            SELECT COUNT(*) FROM vectors v JOIN documents d ON d.hash = v.hash
            WHERE d.base = ? AND v.profile = ? AND v.revision = ?
            """, bind: { stmt in
                sqlite3_bind_text(stmt, 1, base, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, EmbeddingProfile.e5sV1.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, EmbeddingProfile.e5sV1.modelRevision, -1, SQLITE_TRANSIENT)
            }) { stmt in
                count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    func chunkCount(base: BaseID) -> Int {
        var count = 0
        query("""
            SELECT COUNT(*) FROM chunks c JOIN documents d ON d.hash = c.hash WHERE d.base = ?
            """, bind: { stmt in
                sqlite3_bind_text(stmt, 1, base, -1, SQLITE_TRANSIENT)
            }) { stmt in
                count = Int(sqlite3_column_int64(stmt, 0))
        }
        return count
    }

    // MARK: - Ingest (K-D1/K-D2/K-D3)

    func ingest(mkt: URL, base: BaseID, name: String) throws {
        let document = try MKTCodec.decode(Data(contentsOf: mkt))
        createBase(base)
        run("INSERT OR REPLACE INTO documents(hash, base, name, mime, created_at) VALUES (?, ?, ?, ?, ?)",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, document.sourceHash, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, base, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, document.mime, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, document.createdAt, -1, SQLITE_TRANSIENT)
            })
        run("DELETE FROM chunks WHERE hash = ?", bind: { stmt in
            sqlite3_bind_text(stmt, 1, document.sourceHash, -1, SQLITE_TRANSIENT)
        })
        for chunk in document.chunks {
            run("INSERT INTO chunks(hash, i, text, page, char_start, char_end, tokens) VALUES (?, ?, ?, ?, ?, ?, ?)",
                bind: { stmt in
                    sqlite3_bind_text(stmt, 1, document.sourceHash, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(stmt, 2, Int64(chunk.i))
                    sqlite3_bind_text(stmt, 3, chunk.text, -1, SQLITE_TRANSIENT)
                    if let page = chunk.page {
                        sqlite3_bind_int64(stmt, 3 + 1, Int64(page))
                    } else {
                        sqlite3_bind_null(stmt, 4)
                    }
                    sqlite3_bind_int64(stmt, 5, Int64(chunk.charStart))
                    sqlite3_bind_int64(stmt, 6, Int64(chunk.charEnd))
                    sqlite3_bind_int64(stmt, 7, Int64(chunk.tokens))
                })
        }
    }

    func ingest(mkv: URL) throws {
        let (header, vectors) = try MKVCodec.decode(Data(contentsOf: mkv))
        for (index, vector) in vectors.enumerated() {
            let blob = vector.withUnsafeBufferPointer { buf in
                Data(bytes: buf.baseAddress!, count: buf.count * MemoryLayout<Float>.size)
            }
            run("INSERT OR REPLACE INTO vectors(hash, i, profile, revision, vec) VALUES (?, ?, ?, ?, ?)",
                bind: { stmt in
                    sqlite3_bind_text(stmt, 1, header.sourceHash, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int64(stmt, 2, Int64(index))
                    sqlite3_bind_text(stmt, 3, header.profileID, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 4, header.modelRevision, -1, SQLITE_TRANSIENT)
                    _ = blob.withUnsafeBytes { sqlite3_bind_blob(stmt, 5, $0.baseAddress, Int32(blob.count), SQLITE_TRANSIENT) }
                })
        }
    }

    func removeDocument(hash: String) {
        run("DELETE FROM chunks WHERE hash = ?", bind: { sqlite3_bind_text($0, 1, hash, -1, SQLITE_TRANSIENT) })
        run("DELETE FROM vectors WHERE hash = ?", bind: { sqlite3_bind_text($0, 1, hash, -1, SQLITE_TRANSIENT) })
        run("DELETE FROM documents WHERE hash = ?", bind: { sqlite3_bind_text($0, 1, hash, -1, SQLITE_TRANSIENT) })
    }

    // MARK: - Search (K-R2/K-R3)

    /// Hybrid: FTS5 BM25 top-20 + cosine top-20 merged with reciprocal rank
    /// fusion (k = 60). queryVector nil → keyword-only (K-R2 fallback).
    func search(_ q: String, queryVector: [Float]?, base: BaseID, limit: Int) -> [Passage] {
        let bm25 = keywordSearch(q, base: base, limit: 20)
        guard let queryVector else {
            return Array(bm25.prefix(limit))
        }
        let semantic = vectorSearch(queryVector, base: base, limit: 20)
        // Reciprocal rank fusion.
        var scores: [String: Double] = [:]
        var passages: [String: Passage] = [:]
        for (rank, passage) in bm25.enumerated() {
            scores[passage.id, default: 0] += 1.0 / (60.0 + Double(rank + 1))
            passages[passage.id] = passage
        }
        for (rank, passage) in semantic.enumerated() {
            scores[passage.id, default: 0] += 1.0 / (60.0 + Double(rank + 1))
            passages[passage.id] = passage
        }
        return scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { entry in
                guard var passage = passages[entry.key] else { return nil }
                passage.score = entry.value
                return passage
            }
    }

    private func keywordSearch(_ q: String, base: BaseID, limit: Int) -> [Passage] {
        // FTS5 match expression: quote terms to avoid syntax injection.
        let terms = q.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { "\"\($0)\"" }
        guard !terms.isEmpty else { return [] }
        let match = terms.joined(separator: " OR ")
        var result: [Passage] = []
        query("""
            SELECT c.hash, c.i, c.text, c.page, c.char_start, c.char_end, d.name,
                   bm25(chunks_fts) AS rank
            FROM chunks_fts
            JOIN chunks c ON c.rowid = chunks_fts.rowid
            JOIN documents d ON d.hash = c.hash
            WHERE chunks_fts MATCH ? AND d.base = ?
            ORDER BY rank LIMIT ?
            """, bind: { stmt in
                sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, base, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 3, Int64(limit))
            }) { stmt in
                result.append(Passage(
                    id: "\(String(cString: sqlite3_column_text(stmt, 0)))#\(sqlite3_column_int64(stmt, 1))",
                    text: String(cString: sqlite3_column_text(stmt, 2)),
                    sourceName: String(cString: sqlite3_column_text(stmt, 6)),
                    page: sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, 3)),
                    charStart: Int(sqlite3_column_int64(stmt, 4)),
                    charEnd: Int(sqlite3_column_int64(stmt, 5)),
                    score: -sqlite3_column_double(stmt, 7)))
            }
        return result
    }

    private func vectorSearch(_ queryVector: [Float], base: BaseID, limit: Int) -> [Passage] {
        // K-R3: compare against every stored vector with vDSP, fp32 in memory.
        var scored: [(Passage, Float)] = []
        let dims = queryVector.count
        query("""
            SELECT v.hash, v.i, v.vec, c.text, c.page, c.char_start, c.char_end, d.name
            FROM vectors v
            JOIN chunks c ON c.hash = v.hash AND c.i = v.i
            JOIN documents d ON d.hash = v.hash
            WHERE d.base = ? AND v.profile = ? AND v.revision = ?
            """, bind: { stmt in
                sqlite3_bind_text(stmt, 1, base, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, EmbeddingProfile.e5sV1.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, EmbeddingProfile.e5sV1.modelRevision, -1, SQLITE_TRANSIENT)
            }) { stmt in
                guard let blob = sqlite3_column_blob(stmt, 2) else { return }
                let count = Int(sqlite3_column_bytes(stmt, 2)) / MemoryLayout<Float>.size
                guard count == dims else { return }
                let vector = Array(UnsafeBufferPointer(
                    start: blob.assumingMemoryBound(to: Float.self), count: count))
                var dot: Float = 0
                vDSP_dotpr(queryVector, 1, vector, 1, &dot, vDSP_Length(dims))
                let passage = Passage(
                    id: "\(String(cString: sqlite3_column_text(stmt, 0)))#\(sqlite3_column_int64(stmt, 1))",
                    text: String(cString: sqlite3_column_text(stmt, 3)),
                    sourceName: String(cString: sqlite3_column_text(stmt, 7)),
                    page: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(stmt, 4)),
                    charStart: Int(sqlite3_column_int64(stmt, 5)),
                    charEnd: Int(sqlite3_column_int64(stmt, 6)),
                    score: Double(dot))
                scored.append((passage, dot))
            }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// K-R6: plain passage search without an LLM.
    func passages(matching q: String, base: BaseID, limit: Int) -> [Passage] {
        search(q, queryVector: nil, base: base, limit: limit)
    }

    // MARK: - SQLite helpers

    private func run(_ sql: String, bind: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("SQLite prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return
        }
        bind(stmt!)
        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("SQLite step failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
        }
        sqlite3_finalize(stmt)
    }

    private func query(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil, row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("SQLite prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return
        }
        bind?(stmt!)
        while sqlite3_step(stmt) == SQLITE_ROW {
            row(stmt!)
        }
        sqlite3_finalize(stmt)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

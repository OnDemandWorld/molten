//
//  ConversationSearch.swift
//  Molten
//
//  Molten 2.0 — M6, C1. Full-text search across all conversations via a
//  side SQLite FTS5 table, kept up to date by the data actor on message
//  insert/edit/delete. Results jump to the matching message.
//

import Foundation
import SQLite3
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "conversations.search")

struct ConversationSearchHit: Sendable, Identifiable {
    let id: String // conversationID#messageID
    let conversationID: UUID
    let messageID: UUID
    let conversationName: String
    let snippet: String
    let role: String
}

/// Synchronous, lock-guarded so the data actor can maintain the index from
/// its non-async methods. The database is a local sidecar — never synced.
final class ConversationSearch: @unchecked Sendable {
    static let shared = ConversationSearch()

    private let lock = NSLock()
    private var db: OpaquePointer?

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Molten", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let url = base.appendingPathComponent("conversations.sqlite")
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { return }
        exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                conversation_id, message_id, conversation_name, role, text
            );
            """)
    }

    deinit { if let db { sqlite3_close(db) } }

    // MARK: - Index maintenance (called by SwiftDataService)

    func indexMessage(_ message: MessageSD, conversation: ConversationSD) {
        lock.lock(); defer { lock.unlock() }
        removeMessageRows(messageID: message.id.uuidString)
        let text = message.realContent ?? message.content
        guard !text.isEmpty else { return }
        run("INSERT INTO messages_fts(conversation_id, message_id, conversation_name, role, text) VALUES (?, ?, ?, ?, ?)",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, conversation.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, message.id.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, conversation.name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, message.role, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, text, -1, SQLITE_TRANSIENT)
            })
    }

    func removeMessage(messageID: UUID) {
        lock.lock(); defer { lock.unlock() }
        removeMessageRows(messageID: messageID.uuidString)
    }

    func removeConversation(conversationID: UUID) {
        lock.lock(); defer { lock.unlock() }
        run("DELETE FROM messages_fts WHERE conversation_id = ?",
            bind: { sqlite3_bind_text($0, 1, conversationID.uuidString, -1, SQLITE_TRANSIENT) })
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        exec("DELETE FROM messages_fts;")
    }

    func renameConversation(conversationID: UUID, name: String) {
        lock.lock(); defer { lock.unlock() }
        run("UPDATE messages_fts SET conversation_name = ? WHERE conversation_id = ?",
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, conversationID.uuidString, -1, SQLITE_TRANSIENT)
            })
    }

    /// C1: backfill on first launch (idempotent — clears and rebuilds).
    func rebuild(conversations: [ConversationSD]) {
        lock.lock(); defer { lock.unlock() }
        exec("DELETE FROM messages_fts;")
        for conversation in conversations {
            for message in conversation.messages {
                let text = message.realContent ?? message.content
                guard !text.isEmpty else { continue }
                run("INSERT INTO messages_fts(conversation_id, message_id, conversation_name, role, text) VALUES (?, ?, ?, ?, ?)",
                    bind: { stmt in
                        sqlite3_bind_text(stmt, 1, conversation.id.uuidString, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(stmt, 2, message.id.uuidString, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(stmt, 3, conversation.name, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(stmt, 4, message.role, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(stmt, 5, text, -1, SQLITE_TRANSIENT)
                    })
            }
        }
    }

    // MARK: - Search

    func search(_ query: String, limit: Int = 50) -> [ConversationSearchHit] {
        lock.lock(); defer { lock.unlock() }
        let terms = query.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map { "\"\($0)\"" }
        guard !terms.isEmpty else { return [] }
        let match = terms.joined(separator: " OR ")
        var hits: [ConversationSearchHit] = []
        queryRows("""
            SELECT conversation_id, message_id, conversation_name, role,
                   snippet(messages_fts, 4, '', '', '…', 12)
            FROM messages_fts WHERE messages_fts MATCH ? LIMIT ?
            """, bind: { stmt in
                sqlite3_bind_text(stmt, 1, match, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 2, Int64(limit))
            }) { stmt in
                guard let cid = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))),
                      let mid = UUID(uuidString: String(cString: sqlite3_column_text(stmt, 1))) else { return }
                hits.append(ConversationSearchHit(
                    id: "\(cid.uuidString)#\(mid.uuidString)",
                    conversationID: cid,
                    messageID: mid,
                    conversationName: String(cString: sqlite3_column_text(stmt, 2)),
                    snippet: String(cString: sqlite3_column_text(stmt, 4)),
                    role: String(cString: sqlite3_column_text(stmt, 3))))
            }
        return hits
    }

    // MARK: - SQLite helpers

    private func removeMessageRows(messageID: String) {
        run("DELETE FROM messages_fts WHERE message_id = ?",
            bind: { sqlite3_bind_text($0, 1, messageID, -1, SQLITE_TRANSIENT) })
    }

    private func exec(_ sql: String) {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            logger.error("Search index exec failed: \(error.map { String(cString: $0) } ?? "", privacy: .public)")
            sqlite3_free(error)
        }
    }

    private func run(_ sql: String, bind: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bind(stmt!)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func queryRows(_ sql: String, bind: (OpaquePointer) -> Void, row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bind(stmt!)
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt!) }
        sqlite3_finalize(stmt)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

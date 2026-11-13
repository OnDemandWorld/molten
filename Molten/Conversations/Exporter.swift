//
//  Exporter.swift
//  Molten
//
//  Molten 2.0 — M6, C2. Export one conversation as Markdown or JSON (with
//  an analytics option), or everything as a zip. Local only.
//

import Foundation
import zlib

struct ExportedAnalytics: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let totalTime: Double?
    let promptEvalTime: Double?
    let evalTime: Double?
}

struct ExportedMessage: Codable, Sendable {
    let role: String
    let content: String
    let createdAt: Date
    let analytics: ExportedAnalytics?
}

struct ExportedConversation: Codable, Sendable {
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let messages: [ExportedMessage]
}

enum Exporter {
    static func exported(_ conversation: ConversationSD, includeAnalytics: Bool) -> ExportedConversation {
        let messages = conversation.messages
            .sorted { $0.createdAt < $1.createdAt }
            .map { message in
                ExportedMessage(
                    role: message.role,
                    content: message.realContent ?? message.content,
                    createdAt: message.createdAt,
                    analytics: includeAnalytics ? ExportedAnalytics(
                        promptTokens: message.promptTokens,
                        completionTokens: message.completionTokens,
                        totalTokens: message.totalTokens,
                        totalTime: message.totalTime,
                        promptEvalTime: message.promptEvalTime,
                        evalTime: message.evalTime) : nil)
            }
        return ExportedConversation(
            name: conversation.name,
            createdAt: conversation.createdAt,
            updatedAt: conversation.updatedAt,
            messages: messages)
    }

    static func json(_ conversation: ConversationSD, includeAnalytics: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exported(conversation, includeAnalytics: includeAnalytics))
    }

    static func markdown(_ conversation: ConversationSD, includeAnalytics: Bool) -> String {
        var out = "# \(conversation.name)\n\n"
        let formatter = ISO8601DateFormatter()
        out += "_Created: \(formatter.string(from: conversation.createdAt))_\n\n"
        for message in conversation.messages.sorted(by: { $0.createdAt < $1.createdAt }) {
            out += "## \(message.role.capitalized)\n\n"
            out += (message.realContent ?? message.content) + "\n\n"
            if includeAnalytics, let tokens = message.totalTokens {
                out += "_Tokens: \(tokens)"
                if let time = message.totalTime { out += String(format: " · Time: %.1fs", time) }
                out += "_\n\n"
            }
        }
        return out
    }

    /// C2: export everything as a zip (one JSON file per conversation).
    static func zipAll(_ conversations: [ConversationSD], includeAnalytics: Bool) throws -> Data {
        var files: [(name: String, data: Data)] = []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for (index, conversation) in conversations.enumerated() {
            let safe = conversation.name
                .components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|"))
                .joined(separator: "-")
            let name = String(format: "%03d-%@.json", index + 1, String(safe.prefix(60)))
            files.append((name, try encoder.encode(exported(conversation, includeAnalytics: includeAnalytics))))
        }
        return ZipWriter.archive(files: files)
    }
}

// MARK: - Minimal stored (uncompressed) ZIP writer

enum ZipWriter {
    static func archive(files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        var offset: UInt32 = 0
        for file in files {
            let nameData = Data(file.name.utf8)
            let crc = UInt32(crc32(0, file.data.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress }, UInt32(file.data.count)))
            let size = UInt32(file.data.count)
            // Local file header
            out.append(le32(0x04034b50))
            out.append(le16(20))          // version needed
            out.append(le16(0))           // flags
            out.append(le16(0))           // method: stored
            out.append(le16(0))           // mod time
            out.append(le16(0x21))        // mod date (1980-01-01)
            out.append(le32(crc))
            out.append(le32(size))
            out.append(le32(size))
            out.append(le16(UInt16(nameData.count)))
            out.append(le16(0))           // extra len
            out.append(nameData)
            out.append(file.data)
            // Central directory entry
            central.append(le32(0x02014b50))
            central.append(le16(20))
            central.append(le16(20))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0x21))
            central.append(le32(crc))
            central.append(le32(size))
            central.append(le32(size))
            central.append(le16(UInt16(nameData.count)))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le16(0))
            central.append(le32(0))
            central.append(le32(offset))
            central.append(nameData)
            offset += UInt32(30 + nameData.count + file.data.count)
        }
        let centralOffset = offset
        out.append(central)
        // End of central directory
        out.append(le32(0x06054b50))
        out.append(le16(0))
        out.append(le16(0))
        out.append(le16(UInt16(files.count)))
        out.append(le16(UInt16(files.count)))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))
        return out
    }

    private static func le16(_ value: UInt16) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 2)
    }
    private static func le32(_ value: UInt32) -> Data {
        var v = value.littleEndian
        return Data(bytes: &v, count: 4)
    }
}

//
//  MessageSD.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData

@Model
final class MessageSD: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()

    // Cached think parsing results to avoid repeated string scans
    // These are computed once and cached for performance
    private var cachedThink: String?
    private var cachedHasThink: Bool?
    private var cachedThinkComplete: Bool?
    private var cachedRealContent: String?
    private var lastContentScan: String?

    // Invalidate cache when content changes
    private func ensureCacheValid(_ content: String) {
        if lastContentScan != content {
            lastContentScan = content
            cachedThink = nil
            cachedHasThink = nil
            cachedThinkComplete = nil
            cachedRealContent = nil
        }
    }

    private func parseThink(from content: String) -> (hasThink: Bool, think: String?, thinkComplete: Bool, realContent: String?) {
        guard content.contains("<think>") else {
            return (false, nil, false, content)
        }

        let thinkStart = "<think>"
        let thinkEnd = "</think>"

        guard let startRange = content.range(of: thinkStart) else {
            return (false, nil, false, content)
        }

        let hasThink = true
        let thinkComplete = content.range(of: thinkEnd) != nil

        if thinkComplete {
            // Extract think content between <think> and </think>
            guard let endRange = content.range(of: thinkEnd) else {
                return (hasThink, nil, false, content)
            }
            let thinkContent = String(content[startRange.upperBound..<endRange.lowerBound])
            let realContent = String(content[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (hasThink, thinkContent, thinkComplete, realContent.isEmpty ? nil : realContent)
        } else {
            // Think tag present but not complete
            let thinkContent = String(content[startRange.upperBound...])
            return (hasThink, thinkContent, false, nil)
        }
    }

    var think: String? {
        ensureCacheValid(content)
        if cachedThink == nil {
            cachedThink = parseThink(from: content).think
        }
        return cachedThink
    }

    var hasThink: Bool {
        ensureCacheValid(content)
        if cachedHasThink == nil {
            cachedHasThink = parseThink(from: content).hasThink
        }
        return cachedHasThink ?? false
    }

    var thinkComplete: Bool {
        ensureCacheValid(content)
        if cachedThinkComplete == nil {
            cachedThinkComplete = parseThink(from: content).thinkComplete
        }
        return cachedThinkComplete ?? false
    }

    var realContent: String? {
        ensureCacheValid(content)
        if cachedRealContent == nil {
            cachedRealContent = parseThink(from: content).realContent
        }
        return cachedRealContent
    }

    var content: String
    var role: String
    var done: Bool = false
    var error: Bool = false
    var createdAt: Date = Date.now
    @Attribute(.externalStorage) var image: Data?

    // Analytics fields
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var promptEvalTime: TimeInterval? // Time from request start to first token
    var evalTime: TimeInterval? // Time from first token to completion
    var totalTime: TimeInterval? // Total time from request start to completion

    @Relationship var conversation: ConversationSD?


    init(content: String, role: String, done: Bool = false, error: Bool = false, image: Data? = nil) {
        self.content = content
        self.role = role
        self.done = done
        self.error = error
        self.conversation = conversation
        self.image = image
        // Initialize cache for initial content
        self.lastContentScan = content
        let parsed = parseThink(from: content)
        self.cachedHasThink = parsed.hasThink
        self.cachedThink = parsed.think
        self.cachedThinkComplete = parsed.thinkComplete
        self.cachedRealContent = parsed.realContent
    }

    @Transient var model: String {
        conversation?.model?.name ?? ""
    }
}

extension MessageSD {
    @MainActor static let sample: [MessageSD] = [
        .init(content: "How many quarks there are in SM?", role: "user"),
        .init(content: "There are 6 quarks in SM, each of them has an antiparticle and colour.", role: "assistant"),
        .init(content: "How elementary particle is defined in mathematics?", role: "user"),
        .init(content: "Elementary particle is defined as an irreducible representation of the poincase group.", role: "assistant")
    ]
}

//
//  ConversationSD.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import Foundation
import SwiftData

@Model
final class MessageSD: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    
    var think: String? {
        if content.contains("<think>") {
            if content.contains("</think>") {
                let tmps = content.components(separatedBy: "</think>")
                if tmps.count > 1 {
                    return tmps[0].replacingOccurrences(of: "<think>", with: "")
                }
            }
            return content.replacingOccurrences(of: "<think>", with: "")
        }
        return nil
    }
    var hasThink: Bool {
        if content.contains("<think>") {
            return true
        }
        return false
    }
    var thinkComplete: Bool {
        if content.contains("<think>") {
            if content.contains("</think>") {
                return true
            }
        }
        return false
    }
    var content: String
    var realContent: String? {
        if content.contains("<think>") {
            if content.contains("</think>") {
                let tmps = content.components(separatedBy: "</think>")
                if tmps.count > 1 {
                    return tmps[1]
                }
            }
            return nil
        }
        return content
    }
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

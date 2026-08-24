//
//  SamplePrompt.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 11/02/2024.
//

import Foundation

struct SamplePrompts: Identifiable, Hashable {
    enum SamplePromptType {
        case question
        case action
        
        var icon: String {
            switch self {
            case .question:
                return "questionmark.circle"
            case .action:
                return "lightbulb.circle"
            }
        }
    }
    
    var prompt: String
    var type: SamplePromptType
    
    var id: String {
        prompt
    }
}

// MARK: - Sample Data
extension SamplePrompts {
    static let samples: [SamplePrompts] = [
        // Kept short on purpose: the front page shows 4 of these in small
        // grid cards, so each prompt should read at a glance (~<50 chars).
        .init(prompt: "Why is the night sky dark?", type: .question),
        .init(prompt: "Explain quantum entanglement to a 5-year-old", type: .action),
        .init(prompt: "Write a haiku about debugging code", type: .action),
        .init(prompt: "What's special about the number 1729?", type: .question),
        .init(prompt: "How do I center a div?", type: .question),
        .init(prompt: "Give 10 dinner ideas with only 5 ingredients", type: .action),
        .init(prompt: "Why should I switch doors on Monty Hall?", type: .question),
        .init(prompt: "Draft a polite way to decline a meeting", type: .action),
        .init(prompt: "What makes Apple Silicon good at running AI?", type: .question),
        .init(prompt: "Write a bedtime story about a brave little toaster", type: .action),
        .init(prompt: "REST vs GraphQL — compare in a table", type: .question),
        .init(prompt: "How does quantization shrink AI models?", type: .question),
        .init(prompt: "Help me name my new cat", type: .action),
        .init(prompt: "Explain recursion using only kitchen analogies", type: .action),
        .init(prompt: "What would a city on Mars need to survive?", type: .question),
        .init(prompt: "Write a limerick about my WiFi dropping", type: .action),
        .init(prompt: "What is a monad? Answer in one paragraph", type: .question),
        .init(prompt: "Plan a 3-day weekend trip to Tokyo", type: .action),
        .init(prompt: "Why do we dream? The leading theories", type: .question),
        .init(prompt: "Rewrite my next message like Shakespeare", type: .action),
    ]
    
    static var shuffled: [SamplePrompts] {
        return samples.shuffled()
    }
}

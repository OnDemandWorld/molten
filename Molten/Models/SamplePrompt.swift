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
        // Original prompts
        .init(prompt: "Give me phrases to learn in a new language", type: .action),
        .init(prompt: "Act like Mowgli from The Jungle Book and answer questions", type: .action),
        .init(prompt: "How to center div in HTML?", type: .question),
        .init(prompt: "What's unique about Go programming language?", type: .question),
        .init(prompt: "Give 10 gift ideas for best friend", type: .action),
        .init(prompt: "Write a text message asking a friend to be my plus-one at a wedding", type: .action),
        .init(prompt: "Explain supercomputers like I'm five years old", type: .action),
        .init(prompt: "How to do personal taxes in USA?", type: .question),
        .init(prompt: "What are the largest cities in USA in population? Give a table", type: .question),
        .init(prompt: "Give me ideas about New Years resolutions", type: .action),
        .init(prompt: "What is bubble sort? Write example in python", type: .question),
        
        // NEW: Technical & Apple Silicon focused
        .init(prompt: "Why is Apple Silicon better for running LLMs locally vs cloud APIs?", type: .question),
        .init(prompt: "Explain unified memory architecture and why it matters for AI inference", type: .action),
        .init(prompt: "What's the difference between M1 Max, M3 Max, and M4 for running language models?", type: .question),
        .init(prompt: "How does quantization allow larger models to run on personal devices?", type: .question),
        
        // NEW: Code & Development
        .init(prompt: "Build me a Swift function that handles API responses with Codable", type: .action),
        .init(prompt: "What are common performance bottlenecks in iOS app development?", type: .question),
        .init(prompt: "Create a regex pattern to validate email addresses", type: .action),
        .init(prompt: "Explain SwiftUI property wrappers: @State, @Binding, @ObservedObject", type: .action),
        
        // NEW: Privacy & Security (relevant to local AI)
        .init(prompt: "Why should sensitive data stay on-device instead of sent to cloud APIs?", type: .question),
        .init(prompt: "What security considerations exist when running AI models locally?", type: .question),
        
        // NEW: Creative & Role-play
        .init(prompt: "Act as a cyberpunk hacker from 2087 and describe your workstation setup", type: .action),
        .init(prompt: "Roleplay as Steve Jobs pitching the original iPhone in 2007", type: .action),
        .init(prompt: "Act as a personal finance advisor and critique my spending habits (give example)", type: .action),
        
        // NEW: Advanced reasoning (showcases chain-of-thought)
        .init(prompt: "Explain step-by-step how you would debug a memory leak in a C++ program", type: .action),
        .init(prompt: "If a train leaves NYC at 2pm going 100mph and another leaves Boston at 3pm going 80mph, when do they meet? Show your work", type: .question),
        .init(prompt: "Design a database schema for a Twitter-like application. Explain your choices", type: .action),
        
        // NEW: Synthesis & Summarization
        .init(prompt: "Summarize the key differences between REST and GraphQL APIs in a table", type: .question),
        .init(prompt: "What are the pros and cons of microservices vs monolithic architecture?", type: .question),
        
        // NEW: Unique/memorable demos
        .init(prompt: "Write a haiku about debugging JavaScript", type: .action),
        .init(prompt: "Create a mock job posting for a 'Full-Stack Wizard' at a fantasy startup", type: .action),
        .init(prompt: "Explain cryptocurrency to a 10-year-old using only analogies", type: .action),
    ]
    
    static var shuffled: [SamplePrompts] {
        return samples.shuffled()
    }
}

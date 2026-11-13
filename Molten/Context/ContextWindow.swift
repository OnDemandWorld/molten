//
//  ContextWindow.swift
//  Molten
//
//  Molten 2.0 — M6, X1. Window sizes: Ollama /api/show, per-server setting
//  for OpenAI-compatible servers (default 8192), 4096 for Apple's on-device
//  model. Warnings at 80% and 95%.
//

import Foundation

enum ContextWindow {
    static let defaultWindow = 8192
    static let appleWindow = 4096
    static let warningThreshold = 0.80
    static let criticalThreshold = 0.95

    static func window(for model: LanguageModelSD) async -> Int {
        switch model.modelProvider {
        case .appleFoundation:
            return appleWindow
        case .ollama:
            return await OllamaService.shared.contextLength(model: model.name) ?? defaultWindow
        default:
            return UserDefaults.standard.object(forKey: "swamaContextWindow") as? Int ?? defaultWindow
        }
    }

    static func usageFraction(used: Int, window: Int) -> Double {
        guard window > 0 else { return 0 }
        return Double(used) / Double(window)
    }
}

//
//  LanguageModelStore.swift
//  Molten
//
//  Manages available language models from all providers.
//  Handles model discovery, caching, and selection.
//
//  Key Responsibilities:
//  - Fetching models from all available providers (Ollama, Swama, Apple)
//  - Caching models locally in SwiftData
//  - Filtering to show only available models
//  - Model selection and persistence
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//  Refactored for Molten v1.0.0
//

import Foundation
import SwiftData

@Observable
final class LanguageModelStore {
    nonisolated(unsafe) static let shared = LanguageModelStore(swiftDataService: SwiftDataService.shared)
    
    private var swiftDataService: SwiftDataService
    @MainActor var models: [LanguageModelSD] = []
    @MainActor var supportsImages = false
    @MainActor var selectedModel: LanguageModelSD?
    
    init(swiftDataService: SwiftDataService) {
        self.swiftDataService = swiftDataService
    }
    
    @MainActor
    func setModel(model: LanguageModelSD?) {
        if let model = model {
            // check if model still exists
            if models.contains(model) {
                selectedModel = model
            }
        } else {
            selectedModel = nil
        }
    }
    
    @MainActor
    func setModel(modelName: String) {
        for model in models {
            if model.name == modelName {
                setModel(model: model)
                return
            }
        }
        if let lastModel = models.last {
            setModel(model: lastModel)
        }
    }
    
    func loadModels() async throws {
        var allModels: [LanguageModel] = []
        
        // Check and load from Swama
        if await SwamaService.shared.reachable() {
            do {
                let swamaModels = try await SwamaService.shared.getModels()
                allModels.append(contentsOf: swamaModels)
            } catch {
                // Log error but continue with other providers
                print("Failed to load Swama models: \(error.localizedDescription)")
            }
        }
        
        // Check and load from Ollama
        if await OllamaService.shared.reachable() {
            do {
                let ollamaModels = try await OllamaService.shared.getModels()
                allModels.append(contentsOf: ollamaModels)
            } catch {
                print("Failed to load Ollama models: \(error.localizedDescription)")
            }
        }
        
        // Check and load from Apple Foundation
        if await AppleFoundationService.shared.reachable() {
            do {
                let appleModels = try await AppleFoundationService.shared.getModels()
                allModels.append(contentsOf: appleModels)
            } catch {
                print("Failed to load Apple Foundation models: \(error.localizedDescription)")
            }
        }
        
        // Save all models to SwiftData
        let modelsToSave = allModels.map { model in
            LanguageModelSD(
                name: model.name,
                imageSupport: model.imageSupport,
                modelProvider: model.provider
            )
        }
        try await swiftDataService.saveModels(models: modelsToSave)
        
        // Load stored models and filter to only available ones
        let storedModels = (try? await swiftDataService.fetchModels()) ?? []
        
        DispatchQueue.main.async {
            let availableModelNames = allModels.map { $0.name }
            self.models = storedModels.filter { availableModelNames.contains($0.name) }
            
            // Update image support flag based on selected model
            if let selected = self.selectedModel {
                self.supportsImages = selected.supportsImages
            } else {
                self.supportsImages = false
            }
        }
    }
    
    func deleteAllModels() async throws {
        DispatchQueue.main.async {
            self.models = []
        }
        try await swiftDataService.deleteModels()
    }
}

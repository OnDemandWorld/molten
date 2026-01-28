//
//  ApplicationEntry.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 12/02/2024.
//

import SwiftUI
import SwiftData

struct ApplicationEntry: View {
    @AppStorage("colorScheme") private var colorScheme: AppColorScheme = .system
    @State private var languageModelStore = LanguageModelStore.shared
    @State private var conversationStore = ConversationStore.shared
    @State private var completionsStore = CompletionsStore.shared
    @State private var appStore = AppStore.shared
    
    var body: some View {
        VStack {
            switch appStore.appState {
            case .chat:
                Chat(languageModelStore: languageModelStore, conversationStore: conversationStore, appStore: appStore)
            case .voice:
                Voice(languageModelStore: languageModelStore, conversationStore: conversationStore, appStore: appStore)
            }
        }
        .task {
            // Load models and conversations on app start
            do {
                try await languageModelStore.loadModels()
            } catch {
                print("Failed to load models: \(error).")
            }
            
            do {
                try await conversationStore.loadConversations()
            } catch {
                print("Failed to load conversations: \(error).")
            }
            
            completionsStore.load()
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
    }
}


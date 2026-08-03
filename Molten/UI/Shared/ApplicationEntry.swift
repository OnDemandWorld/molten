//
//  ApplicationEntry.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 12/02/2024.
//

import SwiftUI
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "startup")

struct ApplicationEntry: View {
    @AppStorage("colorScheme") private var colorScheme: AppColorScheme = .system
    @State private var languageModelStore = LanguageModelStore.shared
    @State private var conversationStore = ConversationStore.shared
    @State private var completionsStore = CompletionsStore.shared
    @State private var appStore = AppStore.shared
    
    var body: some View {
        VStack {
            Chat(languageModelStore: languageModelStore, conversationStore: conversationStore, appStore: appStore)
        }
        .task {
            // Load models and conversations on app start
            do {
                try await languageModelStore.loadModels()
            } catch {
                logger.error("Failed to load models: \(error.localizedDescription, privacy: .private)")
            }

            do {
                try await conversationStore.loadConversations()
            } catch {
                logger.error("Failed to load conversations: \(error.localizedDescription, privacy: .private)")
            }
            
            completionsStore.load()
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
    }
}


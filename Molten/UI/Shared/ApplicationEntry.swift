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
    @State private var entitlementUI = EntitlementUIModel.shared

    var body: some View {
        VStack {
            Chat(languageModelStore: languageModelStore, conversationStore: conversationStore, appStore: appStore)
        }
        // M5: one-time Early Supporter thank-you sheet.
        .sheet(isPresented: Bindable(entitlementUI).showEarlySupporterThankYou) {
            EarlySupporterThankYouView()
        }
        .task {
            #if DEBUG
            // K-S6: verify the shared iCloud container resolves as expected.
            KnowledgeContainer.debugCheck()
            #endif

            // M8: entitlements listener + evaluation from launch.
            await EntitlementManager.shared.start()

            // M4: resolve the Knowledge root (Plus → iCloud), migrate local
            // bases on upgrade, start sync watchers.
            await KnowledgeContainer.resolveRoot()
            try? await KnowledgeContainer.migrateLocalToICloud()
            KnowledgeSync.shared.start()

            // M5: heartbeat while active (K-P5); Mac auto-indexes (K-P3).
            await HeartbeatService.shared.start {
                DeviceRoles.allowedStages(policy: DeviceRoles.policy, isCharging: DeviceRoles.isCharging).contains(.embed)
            }
            #if os(macOS)
            if UserDefaults.standard.object(forKey: "knowledgeKeepIndexing") as? Bool ?? true {
                for base in await KnowledgeStore.shared.bases() {
                    try? await KnowledgeIndexer.shared.scan(base: base)
                }
            }
            #endif

            // Load models and conversations on app start
            do {
                try await languageModelStore.loadModels()
            } catch {
                logger.error("Failed to load models: \(error.localizedDescription, privacy: .private)")
            }

            do {
                try await conversationStore.loadConversations()
                // C1: backfill the search index for pre-2.0 conversations —
                // incremental indexing only sees messages written from now on.
                if ConversationSearch.shared.isEmpty() {
                    let conversations = (try? await SwiftDataService.shared.fetchConversations()) ?? []
                    ConversationSearch.shared.rebuild(conversations: conversations)
                }
            } catch {
                logger.error("Failed to load conversations: \(error.localizedDescription, privacy: .private)")
            }

            completionsStore.load()
        }
        .preferredColorScheme(colorScheme.toiOSFormat)
    }
}


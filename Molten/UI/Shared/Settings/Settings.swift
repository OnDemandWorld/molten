//
//  Settings.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 28/12/2023.
//

import SwiftUI

struct Settings: View {
    var languageModelStore = LanguageModelStore.shared
    var conversationStore = ConversationStore.shared
    var swiftDataService = SwiftDataService.shared
    
    // Provider config are drafts, committed only on Save: @AppStorage
    // write-through meant "Cancel" still persisted every keystroke and a
    // cancelled URL became active on next launch (review 2026-11-24).
    @State private var swamaUri: String = ""
    @State private var ollamaUri: String = ""
    @State private var ollamaBearerToken: String = ""
    @State private var swamaApiKey: String = ""
    @AppStorage("systemPrompt") private var systemPrompt: String = ""
    @AppStorage("vibrations") private var vibrations: Bool = true
    @AppStorage("colorScheme") private var colorScheme = AppColorScheme.system
    @AppStorage("defaultModel") private var defaultModel: String = ""
    @AppStorage("appUserInitials") private var appUserInitials: String = ""
    @AppStorage("pingInterval") private var pingInterval: String = {
        #if os(macOS)
        return "15"
        #else
        return "30"
        #endif
    }()
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = ""
    
    @StateObject private var speechSynthesiser = SpeechSynthesizer.shared

    @Environment(\.presentationMode) var presentationMode

    private func save() {
        // Remove trailing slashes
        while swamaUri.hasSuffix("/") { swamaUri.removeLast() }
        while ollamaUri.hasSuffix("/") { ollamaUri.removeLast() }

        // Commit the drafts. An empty string is meaningful (it disables the
        // provider) — but only when the key already exists: writing "" for
        // a never-configured provider would disable it on a plain Save.
        commitDraft(swamaUri, forKey: "swamaUri")
        commitDraft(ollamaUri, forKey: "ollamaUri")
        commitDraft(ollamaBearerToken, forKey: "ollamaBearerToken")
        commitDraft(swamaApiKey, forKey: "swamaApiKey")

        SwamaService.shared.initEndpoint(url: swamaUri, apiKey: swamaApiKey)
        OllamaService.shared.initEndpoint(url: ollamaUri, bearerToken: ollamaBearerToken)
        AppStore.shared.applyPingInterval()

        Task {
            Haptics.shared.mediumTap()
            try? await languageModelStore.loadModels()
        }
        presentationMode.wrappedValue.dismiss()
    }
    
    private func commitDraft(_ value: String, forKey key: String) {
        if value.isEmpty && UserDefaults.standard.object(forKey: key) == nil { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func checkServer() {
        Task {
            SwamaService.shared.initEndpoint(url: swamaUri, apiKey: swamaApiKey)
            OllamaService.shared.initEndpoint(url: ollamaUri, bearerToken: ollamaBearerToken)
            // Force immediate check (bypasses cache)
            swamaStatus = await SwamaService.shared.reachable()
            ollamaStatus = await OllamaService.shared.reachable()
            // Also update AppStore's reachability cache
            AppStore.shared.forceReachabilityCheck()
            try? await languageModelStore.loadModels()
        }
    }
    
    private func deleteAll() {
        Task {
            conversationStore.deleteAllConversations()
            try? await languageModelStore.deleteAllModels()
        }
    }
    
    @State var swamaStatus: Bool?
    @State var ollamaStatus: Bool?
    var body: some View {
        SettingsView(
            swamaUri: $swamaUri,
            ollamaUri: $ollamaUri,
            ollamaBearerToken: $ollamaBearerToken,
            systemPrompt: $systemPrompt,
            vibrations: $vibrations,
            colorScheme: $colorScheme,
            defaultModel: $defaultModel, 
            swamaApiKey: $swamaApiKey,
            appUserInitials: $appUserInitials,
            pingInterval: $pingInterval,
            voiceIdentifier: $voiceIdentifier,
            swamaStatus: $swamaStatus,
            ollamaStatus: $ollamaStatus, 
            save: save,
            checkServer: checkServer,
            deleteAll: deleteAll,
            allLanguageModels: languageModelStore.models,
            voices: speechSynthesiser.voices
        )
        .frame(maxWidth: 700)
        .onChange(of: defaultModel) { _, modelName in
            languageModelStore.setModel(modelName: modelName)
        }
        .onAppear {
            // Load provider drafts from the persisted config.
            swamaUri = UserDefaults.standard.string(forKey: "swamaUri") ?? ""
            ollamaUri = UserDefaults.standard.string(forKey: "ollamaUri") ?? ""
            ollamaBearerToken = UserDefaults.standard.string(forKey: "ollamaBearerToken") ?? ""
            swamaApiKey = UserDefaults.standard.string(forKey: "swamaApiKey") ?? ""
            /// Refresh voices once when Settings opens (F-60: previously polled every 5s).
            speechSynthesiser.fetchVoices()
        }
        .onDisappear {
            // Cancel must not leave the live endpoints on unsaved drafts:
            // re-resolve from persisted config (after Save this is a no-op
            // with identical values).
            SwamaService.shared.initEndpoint()
            OllamaService.shared.initEndpoint()
        }
    }
}

#Preview {
    Settings()
}

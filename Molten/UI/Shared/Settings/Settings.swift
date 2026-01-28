//
//  Settings.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 28/12/2023.
//

import SwiftUI
import Combine

struct Settings: View {
    var languageModelStore = LanguageModelStore.shared
    var conversationStore = ConversationStore.shared
    var swiftDataService = SwiftDataService.shared
    
    @AppStorage("swamaUri") private var swamaUri: String = ""
    @AppStorage("ollamaUri") private var ollamaUri: String = ""
    @AppStorage("ollamaBearerToken") private var ollamaBearerToken: String = ""
    @AppStorage("systemPrompt") private var systemPrompt: String = ""
    @AppStorage("vibrations") private var vibrations: Bool = true
    @AppStorage("colorScheme") private var colorScheme = AppColorScheme.system
    @AppStorage("defaultModel") private var defaultModel: String = ""
    @AppStorage("swamaApiKey") private var swamaApiKey: String = ""
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
    
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var cancellable: AnyCancellable?
    
    private func save() {
#if os(iOS)
#endif
        // remove trailing slash
        if swamaUri.last == "/" {
            swamaUri = String(swamaUri.dropLast())
        }
        
        // Remove trailing slashes
        if swamaUri.last == "/" {
            swamaUri = String(swamaUri.dropLast())
        }
        if ollamaUri.last == "/" {
            ollamaUri = String(ollamaUri.dropLast())
        }
        
        SwamaService.shared.initEndpoint(url: swamaUri, apiKey: swamaApiKey)
        OllamaService.shared.initEndpoint(url: ollamaUri, bearerToken: ollamaBearerToken)
        
        Task {
            Haptics.shared.mediumTap()
            try? await languageModelStore.loadModels()
        }
        presentationMode.wrappedValue.dismiss()
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
        #if os(visionOS)
        .frame(minWidth: 600, minHeight: 800)
        #endif
        .onChange(of: defaultModel) { _, modelName in
            languageModelStore.setModel(modelName: modelName)
        }
        .onAppear {
            /// refresh voices in the background
            cancellable = timer.sink { _ in
                speechSynthesiser.fetchVoices()
            }
        }
        .onDisappear {
            cancellable?.cancel()
        }
    }
}

#Preview {
    Settings()
}

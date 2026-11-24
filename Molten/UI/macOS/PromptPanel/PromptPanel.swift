//
//  PromptPanel.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 12/02/2024.
//

#if os(macOS)
import SwiftUI

struct PromptPanel: View {
    @AppStorage("colorScheme") private var colorScheme: AppColorScheme = .system
    @AppStorage("systemPrompt") private var systemPrompt: String = ""
    @State var conversationStore = ConversationStore.shared
    @State var languageModelStore = LanguageModelStore.shared
    @State var completionsStore = CompletionsStore.shared
    @State var appStore = AppStore.shared
    @State var completionsPanelVM: CompletionsPanelVM
    var onSubmitPanel: () -> ()
    var onSubmitCompletion: (_ scheduledTyping: Bool) -> ()
    var onLayoutUpdate: () -> ()
    
    @MainActor
    func sendMessage(prompt: String, image: Image?) {
        // No model selected (provider down / first launch / model removed):
        // surface an error instead of trapping on a force unwrap
        // (review 2026-11-24). Matches the guarded completion paths below.
        guard let selectedModel = languageModelStore.selectedModel else {
            appStore.uiLog(message: "No model selected — check that a provider is running", status: .error)
            return
        }
        conversationStore.selectedConversation = nil
        conversationStore.sendPrompt(
            userPrompt: prompt,
            model: selectedModel,
            image: image,
            systemPrompt: systemPrompt
        )
        onSubmitPanel()
    }
    
    @MainActor
    func completionInWindow(_ completion: CompletionInstructionSD, scheduledTyping: Bool) {
        guard let selectedModel = languageModelStore.selectedModel else { return }
        completionsPanelVM.sendPrompt(completion: completion, model: selectedModel)
        onSubmitCompletion(scheduledTyping)
        appStore.uiLog(message: "In Window Completion - **\(completion.name)**", status: .info)
    }
    
    @MainActor
    func completionInApp(_ completion: CompletionInstructionSD) {
        guard languageModelStore.selectedModel != nil else { return }
        let prompt = CompletionsPanelVM.constructPrompt(completion: completion, selectedText: completionsPanelVM.selectedText ?? "")
        sendMessage(prompt: prompt, image: nil)
        appStore.uiLog(message: "In App Completion - **\(completion.name)**", status: .info)
    }
    
    var body: some View {
        Group {
            if let selectedText = completionsPanelVM.selectedText, !selectedText.isEmpty {
                PanelCompletionsView(
                    completions: completionsStore.completions,
                    completionInWindow: completionInWindow,
                    completionInApp: completionInApp
                )
            } else {
                PromptPanelView(
                    onSubmit: sendMessage,
                    onLayoutUpdate: onLayoutUpdate,
                    imageSupport: languageModelStore.selectedModel?.supportsImages ?? false
                )
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}
#endif

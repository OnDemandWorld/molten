//
//  PromptPanelVM.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 29/02/2024.
//

import SwiftUI
import Combine

@Observable
final class CompletionsPanelVM {
    var selectedText: String?
    var onReceiveText: (String) -> ()
    var messageResponse: String = ""
    var isReady = false
    let sentenceQueue = AsyncQueue<String>()
    private var generationTask: Task<Void, Never>?
    private var currentMessageBuffer: String = ""

    
    init(onReceiveText: @escaping (String) -> Void = {_ in}) {
        self.onReceiveText = onReceiveText
    }
    
    static func constructPrompt(completion: CompletionInstructionSD, selectedText: String) -> String {
        var prompt = completion.instruction
        
        if prompt.contains("{{text}}") {
            prompt.replace("{{text}}", with: selectedText)
        } else {
            prompt += " " + selectedText
        }
        
        return prompt
    }
    
    @MainActor
    func sendPrompt(completion: CompletionInstructionSD, model: LanguageModelSD)  {
        guard let selectedText = selectedText, !isReady else { return }
        let prompt = CompletionsPanelVM.constructPrompt(completion: completion, selectedText: selectedText)
        
        let messages: [ChatMessage] = [
            ChatMessage(role: "user", content: prompt, image_url: nil)
        ]
        currentMessageBuffer = ""
        messageResponse = ""
        
        print("request", messages)
        Task {
            if await SwamaService.shared.reachable() {
                generationTask = Task { [weak self] in
                    guard let self = self else { return }
                    
                    do {
                        let stream = SwamaService.shared.chatStream(
                            model: model.name,
                            messages: messages,
                            temperature: completion.modelTemperature.map { Double($0) } ?? 0.8,
                            maxTokens: nil
                        )
                        
                        for try await response in stream {
                            if Task.isCancelled { break }
                            await MainActor.run {
                                self.handleReceive(response)
                            }
                        }
                        
                        if !Task.isCancelled {
                            await MainActor.run {
                                self.handleComplete()
                            }
                        }
                    } catch {
                        if !Task.isCancelled {
                            await MainActor.run {
                                self.handleError(error.localizedDescription)
                            }
                        }
                    }
                }
            } else {
                handleError("Server unreachable")
            }
        }
    }
    
    @MainActor
    private func handleReceive(_ response: ChatCompletionResponse) {
        Task {
            // Handle streaming response - content can be in delta or message
            // Extract text content from ContentType enum
            let deltaContent = response.choices?.first?.delta?.content
            let messageContent = response.choices?.first?.message?.content
            
            let responseContent: String? = {
                if let delta = deltaContent {
                    switch delta {
                    case .string(let text):
                        return text
                    case .array(let parts):
                        return parts.compactMap { $0.text }.joined()
                    }
                } else if let message = messageContent {
                    switch message {
                    case .string(let text):
                        return text
                    case .array(let parts):
                        return parts.compactMap { $0.text }.joined()
                    }
                }
                return nil
            }()
            
            if let responseContent = responseContent, !responseContent.isEmpty {
                await sentenceQueue.enqueue(responseContent)
                self.messageResponse = self.messageResponse + responseContent
            }
        }
    }
    
    @MainActor
    private func handleError(_ errorMessage: String) {
        print("error \(errorMessage)")
    }
    
    @MainActor
    private func handleComplete() {
        print("model response ", self.messageResponse)
    }
    
    @MainActor
    func cancel() {
        generationTask?.cancel()
    }
}

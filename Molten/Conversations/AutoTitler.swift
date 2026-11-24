//
//  AutoTitler.swift
//  Molten
//
//  Molten 2.0 — M6, C3. Auto-titles use Apple's on-device model, falling
//  back to the active model. Users can edit titles; the feature can be
//  turned off in Settings.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "conversations.titles")

actor AutoTitler {
    static let shared = AutoTitler()

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "autoTitles") as? Bool ?? true
    }

    /// Generate a short title after the first exchange, only while the
    /// conversation still carries its default name (the first prompt).
    /// Takes an ID, not a model instance: all reads/writes go through
    /// SwiftDataService so this actor never touches another context's
    /// objects (review 2026-11-24).
    func titleIfNeeded(
        conversationID: UUID,
        fallbackProvider: ModelProviderProtocol?,
        fallbackModel: String?
    ) async {
        guard Self.enabled else { return }
        guard let snapshot = try? await SwiftDataService.shared.titleSnapshot(conversationID: conversationID),
              snapshot.name == snapshot.firstUserContent else { return }

        let prompt = """
            Give this conversation a title of at most 6 words. Reply with only the title, no quotes.
            User: \(String(snapshot.firstUserContent.prefix(500)))
            Assistant: \(String(snapshot.firstAssistantContent.prefix(500)))
            """
        var title: String?
        // C3: Apple's on-device model first.
        if await AppleFoundationService.shared.reachable() {
            title = await Self.collect(provider: AppleFoundationService.shared, model: "apple-foundation-model", prompt: prompt)
        }
        if title == nil, let fallbackProvider, let fallbackModel {
            title = await Self.collect(provider: fallbackProvider, model: fallbackModel, prompt: prompt)
        }
        guard let clean = title?.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.")),
              !clean.isEmpty else { return }
        do {
            try await SwiftDataService.shared.renameConversation(
                id: conversationID, name: String(clean.prefix(80)))
        } catch {
            logger.error("Auto-title save failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    private static func collect(provider: ModelProviderProtocol, model: String, prompt: String) async -> String? {
        var text = ""
        do {
            let stream = provider.chatStream(
                model: model,
                messages: [ChatMessage(role: "user", content: prompt, image_url: nil)],
                temperature: 0.3,
                maxTokens: 30)
            for try await response in stream {
                if let delta = response.choices?.first?.delta?.content {
                    switch delta {
                    case .string(let s): text += s
                    case .array(let parts): text += parts.compactMap(\.text).joined()
                    }
                }
            }
        } catch {
            return nil
        }
        return text.isEmpty ? nil : text
    }
}

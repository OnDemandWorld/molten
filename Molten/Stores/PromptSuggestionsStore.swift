//
//  PromptSuggestionsStore.swift
//  Molten
//
//  Generates short, personalized conversation starters for the start page
//  using the on-device Apple Foundation Model. All context (recent prompts)
//  and generation stay local — nothing leaves the device. When the model is
//  unavailable (unsupported hardware, simulator) or generation fails, the
//  UI falls back to the static SamplePrompts pool.
//
//  Created for Molten v1.2
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "suggestions")

@MainActor
@Observable
final class PromptSuggestionsStore {
    static let shared = PromptSuggestionsStore()

    /// Generated prompts. May be empty; never the sole source of truth —
    /// the UI always mixes in static samples.
    private(set) var generated: [SamplePrompts] = []

    private var refreshTask: Task<Void, Never>?
    private var hasLoadedCache = false

    private static let cacheKey = "promptSuggestions"
    private static let cacheDateKey = "promptSuggestionsDate"
    /// Regenerate at most once a day: generation is on-device but battery
    /// and model warm-up still matter.
    private static let maxCacheAge: TimeInterval = 24 * 60 * 60

    init() {
        loadCache()
    }

    /// Loads cached suggestions synchronously (in init) and regenerates in
    /// the background when the cache is stale or empty. Never blocks the UI.
    func refreshIfNeeded() {
        guard refreshTask == nil else { return }
        let stale = Date().timeIntervalSince(lastGenerationDate) > Self.maxCacheAge
        if !generated.isEmpty && !stale { return }

        refreshTask = Task {
            defer { refreshTask = nil }

            let recent = await recentUserPrompts()
            guard let raw = await AppleFoundationService.shared.respond(
                prompt: Self.buildPrompt(recentTopics: recent),
                instructions: Self.instructions
            ) else {
                logger.debug("PromptSuggestions: model unavailable or generation failed; keeping static pool")
                return
            }

            let parsed = Self.parseSuggestions(raw)
            guard !parsed.isEmpty else { return }

            generated = parsed.map { SamplePrompts(prompt: $0, type: .question) }
            saveCache(parsed)
            logger.info("PromptSuggestions: refreshed \(parsed.count) suggestions")
        }
    }

    /// What the start page shows: generated prompts (up to `generatedCount`)
    /// mixed with static samples so the grid is never empty or stale-looking.
    func mixPrompts(total: Int = 4, generatedCount: Int = 2) -> [SamplePrompts] {
        let picked = Array(generated.shuffled().prefix(generatedCount))
        let pickedTexts = Set(picked.map(\.prompt))
        let filler = SamplePrompts.samples
            .filter { !pickedTexts.contains($0.prompt) }
            .shuffled()
            .prefix(max(0, total - picked.count))
        return Array((picked + filler).shuffled())
    }

    // MARK: - Recent context

    /// Recent user prompts across the newest conversations, truncated to
    /// keep the meta-prompt small. Never includes assistant content.
    private func recentUserPrompts(limit: Int = 8) async -> [String] {
        guard let conversations = try? await SwiftDataService.shared.fetchConversations() else {
            return []
        }

        var seen = Set<String>()
        var prompts: [String] = []
        for conversation in conversations.prefix(5) {
            let userMessages = conversation.messages
                .filter { $0.role == "user" }
                .sorted { $0.createdAt > $1.createdAt }
            for message in userMessages {
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, seen.insert(text).inserted else { continue }
                prompts.append(String(text.prefix(120)))
                if prompts.count >= limit { return prompts }
            }
        }
        return prompts
    }

    // MARK: - Model prompting

    private static let instructions = """
    You generate conversation-starter suggestions for a chat app's start page. \
    Keep every suggestion short (at most 8 words), specific, and curiosity-provoking. \
    Never repeat personal details back at the user; never produce offensive content.
    """

    private static func buildPrompt(recentTopics: [String]) -> String {
        var prompt = "The user recently chatted about:\n"
        if recentTopics.isEmpty {
            prompt += "- (nothing yet — surprise them)\n"
        } else {
            for topic in recentTopics {
                prompt += "- \(topic)\n"
            }
        }
        prompt += """
        Generate exactly 6 new conversation starters loosely inspired by these topics.
        Format rules: one per line, no numbering, no quotation marks, no bullet characters.
        Vary the style — some questions, some creative requests. Each under 8 words.
        """
        return prompt
    }

    // MARK: - Parsing (pure; covered by unit tests)

    /// Cleans raw model output into display-ready prompts: splits lines,
    /// strips numbering/bullets/quotes, enforces length and count caps,
    /// and de-duplicates. Internal for unit tests.
    static func parseSuggestions(_ raw: String, maxCount: Int = 6, maxLength: Int = 60) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for line in raw.split(separator: "\n") {
            var text = line.trimmingCharacters(in: .whitespaces)

            // Strip list markers: "-", "*", "•", "·"
            while let first = text.first, first == "-" || first == "*" || first == "•" || first == "·" {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            }

            // Strip leading numbering like "1." or "2)"
            if let separatorIndex = text.firstIndex(where: { $0 == "." || $0 == ")" }),
               !text[..<separatorIndex].isEmpty,
               text[..<separatorIndex].allSatisfy(\.isNumber) {
                text = String(text[text.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
            }

            // Strip surrounding quotes
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))

            guard !text.isEmpty, text.count <= maxLength else { continue }
            guard seen.insert(text.lowercased()).inserted else { continue }

            result.append(text)
            if result.count >= maxCount { break }
        }
        return result
    }

    // MARK: - Cache

    private var lastGenerationDate: Date {
        let timestamp = UserDefaults.standard.double(forKey: Self.cacheDateKey)
        return Date(timeIntervalSince1970: timestamp)
    }

    private func loadCache() {
        guard !hasLoadedCache else { return }
        hasLoadedCache = true
        let stored = UserDefaults.standard.stringArray(forKey: Self.cacheKey) ?? []
        generated = Self.parseSuggestions(stored.joined(separator: "\n"))
            .map { SamplePrompts(prompt: $0, type: .question) }
    }

    private func saveCache(_ prompts: [String]) {
        UserDefaults.standard.set(prompts, forKey: Self.cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.cacheDateKey)
    }
}

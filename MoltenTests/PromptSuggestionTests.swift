//
//  PromptSuggestionTests.swift
//  MoltenTests
//
//  Coverage for start-page prompt suggestion parsing and mixing
//  (PromptSuggestionsStore). Model generation itself is on-device and
//  not unit-testable; the pure parsing/mixing layer is.
//

import XCTest
@testable import Molten

@MainActor
final class PromptSuggestionTests: XCTestCase {

    // MARK: - parseSuggestions

    func testParseStripsNumberingBulletsAndQuotes() {
        let raw = """
        1. Why do cats purr?
        2) "Write a haiku about rain"
        - How do rockets steer in space?
        • 'Plan a picnic menu for two'
        """

        let parsed = PromptSuggestionsStore.parseSuggestions(raw)

        XCTAssertEqual(parsed, [
            "Why do cats purr?",
            "Write a haiku about rain",
            "How do rockets steer in space?",
            "Plan a picnic menu for two",
        ])
    }

    func testParseSkipsEmptyAndOverlongLines() {
        let overlong = String(repeating: "word ", count: 20) // 100 chars
        let raw = """
        Good prompt?

        \(overlong)
        Another good one
        """

        let parsed = PromptSuggestionsStore.parseSuggestions(raw)

        XCTAssertEqual(parsed, ["Good prompt?", "Another good one"])
    }

    func testParseDeduplicatesCaseInsensitivelyAndCapsCount() {
        let raw = """
        why is the sky blue?
        Why is the sky blue?
        one
        two
        three
        four
        five
        six
        seven
        """

        let parsed = PromptSuggestionsStore.parseSuggestions(raw)

        XCTAssertEqual(parsed.count, 6)
        XCTAssertEqual(parsed.first?.lowercased(), "why is the sky blue?")
        XCTAssertFalse(parsed.contains("seven"))
    }

    func testParseHandlesEmptyInput() {
        XCTAssertEqual(PromptSuggestionsStore.parseSuggestions(""), [])
        XCTAssertEqual(PromptSuggestionsStore.parseSuggestions("   \n\n  "), [])
    }

    func testParsePreservesLeadingDecimals() {
        let parsed = PromptSuggestionsStore.parseSuggestions("3.14 ways to compute pi")
        XCTAssertEqual(parsed, ["3.14 ways to compute pi"])
    }

    // MARK: - mixPrompts

    /// The test bundle is hosted in Molten.app, so UserDefaults.standard can
    /// hold the app's real suggestion cache. Give each store a fresh,
    /// isolated defaults suite so tests don't depend on prior app usage.
    private func makeStore() -> PromptSuggestionsStore {
        let suiteName = "PromptSuggestionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return PromptSuggestionsStore(defaults: defaults)
    }

    func testMixFallsBackEntirelyToStaticPoolWhenNothingGenerated() {
        let store = makeStore()

        let mix = store.mixPrompts(total: 4, generatedCount: 2)

        XCTAssertEqual(mix.count, 4)
        let staticTexts = Set(SamplePrompts.samples.map(\.prompt))
        XCTAssertTrue(mix.allSatisfy { staticTexts.contains($0.prompt) })
    }

    func testMixNeverDuplicatesPrompts() {
        let store = makeStore()

        // Run repeatedly because the mix is shuffled.
        for _ in 0..<20 {
            let mix = store.mixPrompts(total: 4, generatedCount: 2)
            XCTAssertEqual(Set(mix.map(\.prompt)).count, mix.count)
        }
    }
}

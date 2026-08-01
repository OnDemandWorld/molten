//
//  ConversationStoreErrorTests.swift
//  MoltenTests
//
//  Regression coverage for audit finding F-20:
//  failures while preparing a prompt must surface as an error state so the
//  UI never stays stuck in .loading.
//

import XCTest
import SwiftData
@testable import Molten

@MainActor
final class ConversationStoreErrorTests: XCTestCase {

    /// A model with no provider makes sendPrompt take its error path after
    /// the setup steps succeed, exercising the same terminal .error state the
    /// new setup do/catch produces.
    func testSendPromptSurfacesErrorStateWhenProviderUnknown() async throws {
        let service = SwiftDataService(inMemory: true)
        let store = ConversationStore(swiftDataService: service)

        let model = LanguageModelSD(name: "no-provider", modelProvider: .swama)
        model.modelProvider = nil // getProvider(for:) -> nil -> error path

        store.sendPrompt(userPrompt: "hello", model: model)

        // sendPrompt performs its work in an unstructured Task; wait for the
        // terminal state instead of assuming synchronous completion.
        let deadline = Date().addingTimeInterval(5)
        while store.conversationState == .loading, Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        guard case .error = store.conversationState else {
            return XCTFail("Expected .error state, got \(String(describing: store.conversationState))")
        }
    }

    /// Empty/whitespace prompts are rejected before any state change.
    func testSendPromptRejectsBlankPromptWithoutLoading() async throws {
        let service = SwiftDataService(inMemory: true)
        let store = ConversationStore(swiftDataService: service)
        let model = LanguageModelSD(name: "no-provider", modelProvider: .swama)

        store.sendPrompt(userPrompt: "   \n ", model: model)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertNotEqual(store.conversationState, .loading)
    }
}

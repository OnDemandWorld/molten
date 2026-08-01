//
//  ApplePromptTests.swift
//  MoltenTests
//
//  Regression coverage for audit finding F-26:
//  the Apple Foundation Models provider must send the full conversation
//  history (all roles), not just the last user message.
//

import XCTest
@testable import Molten

@available(macOS 26.0, iOS 26.0, *)
final class ApplePromptTests: XCTestCase {

    func testConstructPromptIncludesFullMultiTurnHistory() {
        let messages = [
            ChatMessage(role: "system", content: "Be brief.", image_url: nil),
            ChatMessage(role: "user", content: "What is QFT?", image_url: nil),
            ChatMessage(role: "assistant", content: "Quantum field theory.", image_url: nil),
            ChatMessage(role: "user", content: "Who developed it?", image_url: nil),
        ]

        let prompt = AppleFoundationService.constructPrompt(from: messages)

        XCTAssertEqual(
            prompt,
            "System: Be brief.\n\nUser: What is QFT?\n\nAssistant: Quantum field theory.\n\nUser: Who developed it?",
            "All turns, including prior assistant and system turns, must be present"
        )
    }

    func testConstructPromptKeepsEarlierTurnsBeforeLatestUserMessage() {
        let messages = [
            ChatMessage(role: "user", content: "Remember the word apple.", image_url: nil),
            ChatMessage(role: "assistant", content: "OK.", image_url: nil),
            ChatMessage(role: "user", content: "What was the word?", image_url: nil),
        ]

        let prompt = AppleFoundationService.constructPrompt(from: messages)

        XCTAssertTrue(prompt.contains("User: Remember the word apple."))
        XCTAssertTrue(prompt.contains("Assistant: OK."))
        XCTAssertTrue(prompt.contains("User: What was the word?"))
    }

    func testConstructPromptJoinsMultimodalTextParts() {
        var message = ChatMessage(role: "user", content: "placeholder", image_url: nil)
        message.content = .array([
            ContentPart(type: "text", text: "first part", image_url: nil),
            ContentPart(type: "text", text: "second part", image_url: nil),
        ])

        let prompt = AppleFoundationService.constructPrompt(from: [message])

        XCTAssertEqual(prompt, "User: first part second part")
    }

    func testConstructPromptSkipsMessagesWithoutContent() {
        var empty = ChatMessage(role: "user", content: "x", image_url: nil)
        empty.content = nil

        let prompt = AppleFoundationService.constructPrompt(from: [
            empty,
            ChatMessage(role: "user", content: "kept", image_url: nil),
        ])

        XCTAssertEqual(prompt, "User: kept")
    }

    func testConstructPromptEmptyHistory() {
        XCTAssertTrue(AppleFoundationService.constructPrompt(from: []).isEmpty)
    }
}

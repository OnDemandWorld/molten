//
//  PromptAssembler.swift
//  Molten
//
//  Molten 2.0 — M3, K-R4. Injects the top chunks within the context budget,
//  numbered [1]…[n] with file name and page. The instruction tells the model
//  to cite numbers and say when the answer is not in the sources. Apple's
//  on-device model gets at most 3 chunks.
//

import Foundation

struct AssembledContext: Sendable {
    let chunks: [Passage]
    let contextText: String
    let instruction: String
}

enum PromptAssembler {
    static let citationInstruction = """
        Answer using the numbered sources below. Cite the source numbers you \
        use, like [1] or [2]. If the answer is not contained in the sources, \
        say so explicitly instead of guessing.
        """

    static func assemble(
        passages: [Passage],
        budgetTokens: Int,
        isAppleModel: Bool,
        tokenCount: (String) -> Int
    ) -> AssembledContext {
        let maxChunks = isAppleModel ? 3 : 8
        var selected: [Passage] = []
        var used = 0
        for passage in passages.prefix(maxChunks) {
            let entry = format(passage, index: selected.count + 1)
            let cost = tokenCount(entry)
            if used + cost > budgetTokens && !selected.isEmpty { break }
            selected.append(passage)
            used += cost
        }
        let text = selected.enumerated()
            .map { format($0.element, index: $0.offset + 1) }
            .joined(separator: "\n\n")
        return AssembledContext(chunks: selected, contextText: text, instruction: citationInstruction)
    }

    static func format(_ passage: Passage, index: Int) -> String {
        var header = "[\(index)] \(passage.sourceName)"
        if let page = passage.page { header += ", p. \(page)" }
        return header + "\n" + passage.text
    }
}

//
//  TransformersTokenizer.swift
//  Molten
//
//  Molten 2.0 — M1 spike. Adapts huggingface/swift-transformers to
//  MLXLMCommon's Tokenizer/TokenizerLoader protocols (official packages only).
//

import Foundation
import MLXLMCommon
import Tokenizers

/// Loads a tokenizer from a local model directory (tokenizer.json +
/// tokenizer_config.json) via swift-transformers' public AutoTokenizer API.
struct TransformersTokenizerLoader: TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let base = try await AutoTokenizer.from(modelFolder: directory)
        return TransformersTokenizerAdapter(base: base)
    }
}

/// Forwards MLXLMCommon.Tokenizer to swift-transformers. The protocols differ
/// only in argument labels (decode); chat templates are unused by e5 and the
/// MLXLMCommon default extension covers them.
struct TransformersTokenizerAdapter: MLXLMCommon.Tokenizer {
    let base: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        base.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        base.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        base.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        base.convertIdToToken(id)
    }

    var bosToken: String? { base.bosToken }
    var eosToken: String? { base.eosToken }
    var unknownToken: String? { base.unknownToken }

    // e5 is an encoder without a chat template; the protocol has no default.
    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        throw MLXLMCommon.TokenizerError.missingChatTemplate
    }
}

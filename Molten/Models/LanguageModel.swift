//
//  LanguageModel.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 12/05/2024.
//

import Foundation

struct LanguageModel {
    var name: String
    var provider: ModelProvider
    var imageSupport: Bool
}

enum ModelProvider: String, Codable {
    case ollama
    case swama
    case appleFoundation

    /// Accepts both the current raw-value string form and the legacy
    /// keyed-container form (e.g. {"swama":{}}) that Codable synthesis
    /// produced before the enum had a String raw value. Without this,
    /// LanguageModelSD rows persisted by pre-v1.1 builds fail to decode
    /// after updating. Encoding always uses the raw-value string.
    init(from decoder: Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self),
           let provider = ModelProvider(rawValue: raw) {
            self = provider
            return
        }
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        for key in LegacyCodingKeys.allCases where legacy.contains(key) {
            if let provider = ModelProvider(rawValue: key.rawValue) {
                self = provider
                return
            }
        }
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: decoder.codingPath,
            debugDescription: "Unrecognized ModelProvider representation"
        ))
    }

    private enum LegacyCodingKeys: String, CodingKey, CaseIterable {
        case ollama, swama, appleFoundation
    }
}

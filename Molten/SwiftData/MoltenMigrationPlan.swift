//
//  MoltenMigrationPlan.swift
//  Molten
//
//  Molten 2.0 — M6, C4. Versioned schema + migration plan. v1.1 → 2.0 adds
//  only optional properties (attachedKnowledgeBase, knowledgeCitationsData),
//  which SwiftData migrates lightweight automatically; the plan is versioned
//  so future releases can add custom stages. Tested against a v1.1-shaped
//  fixture store (M6 tests).
//

import Foundation
import SwiftData

enum MoltenSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [LanguageModelSD.self, ConversationSD.self, MessageSD.self, CompletionInstructionSD.self]
    }
}

enum MoltenMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [MoltenSchemaV2.self] }
    static var stages: [MigrationStage] { [] }
}

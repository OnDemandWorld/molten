//
//  EntitlementKeychain.swift
//  Molten
//
//  Molten 2.0 — M4. Synchronizable iCloud Keychain item so any device that
//  sees it grants Plus; offline fallback (M11). Injectable for tests (M6).
//

import Foundation
import Security

protocol EarlySupporterStoring: Sendable {
    func save(_ detection: EarlySupporterDetection) -> Bool
    func load() -> EarlySupporterDetection?
}

final class EntitlementKeychain: EarlySupporterStoring {
    static let shared = EntitlementKeychain()

    static let service = "molten.entitlement"
    static let account = "earlySupporter"

    func save(_ detection: EarlySupporterDetection) -> Bool {
        guard let data = try? JSONEncoder().encode(detection) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrSynchronizable as String: true, // M4: syncs via iCloud Keychain
        ]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attrs) { _, new in new }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    func load() -> EarlySupporterDetection? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(EarlySupporterDetection.self, from: data)
    }
}

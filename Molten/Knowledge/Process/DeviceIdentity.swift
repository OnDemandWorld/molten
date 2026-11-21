//
//  DeviceIdentity.swift
//  Molten
//
//  Molten 2.0 — K-P5. Random UUID stored in UserDefaults; no hardware
//  identifiers are used.
//

import Foundation

enum DeviceIdentity {
    static var id: String {
        if let existing = UserDefaults.standard.string(forKey: "moltenDeviceID") {
            return existing
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "moltenDeviceID")
        return new
    }
}

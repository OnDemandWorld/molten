//
//  HapticsService.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 28/12/2023.
//

#if os(iOS)
import UIKit

class Haptics: @unchecked Sendable {
    static let shared = Haptics()
    
    private init() { }

    private func play(_ feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle) {
        // object(forKey:) ?? true: bool(forKey:) returns false when unset,
        // but Settings' @AppStorage default is true — fresh installs showed
        // vibrations ON while nothing fired (review 2026-11-24).
        let vibrations = UserDefaults.standard.object(forKey: "vibrations") as? Bool ?? true
        if vibrations {
            UIImpactFeedbackGenerator(style: feedbackStyle).impactOccurred()
        }
    }
    
    private func notify(_ feedbackType: UINotificationFeedbackGenerator.FeedbackType) {
        // object(forKey:) ?? true: bool(forKey:) returns false when unset,
        // but Settings' @AppStorage default is true — fresh installs showed
        // vibrations ON while nothing fired (review 2026-11-24).
        let vibrations = UserDefaults.standard.object(forKey: "vibrations") as? Bool ?? true
        if vibrations {
            UINotificationFeedbackGenerator().notificationOccurred(feedbackType)
        }
    }
    
    func lightTap() {
        play(.light)
    }
    
    func mediumTap() {
        play(.medium)
    }
}
#else
class Haptics {
    nonisolated(unsafe) static let shared = Haptics()
    func lightTap() {}
    func mediumTap() {}
}
#endif

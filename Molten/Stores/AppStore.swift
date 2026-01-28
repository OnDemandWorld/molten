//
//  AppStore.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import Foundation
import Combine
import SwiftUI

enum AppState {
    case chat
    case voice
}

@Observable
final class AppStore {
    nonisolated(unsafe) static let shared = AppStore()
    
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var pingInterval: TimeInterval = 5
    /// True when at least one provider (Swama, Ollama, or Apple Foundation) is reachable
    @MainActor var isReachable: Bool = true
    @MainActor var notifications: [NotificationMessage] = []
    @MainActor var menuBarIcon: String? = nil
    var appState: AppState = .chat

    init() {
        if let storedIntervalString = UserDefaults.standard.string(forKey: "pingInterval") {
            pingInterval = Double(storedIntervalString) ?? 5
            
            if pingInterval <= 0 {
                pingInterval = .infinity
            }
        }
        startCheckingReachability(interval: pingInterval)
    }
    
    deinit {
        stopCheckingReachability()
    }
    
    private func startCheckingReachability(interval: TimeInterval = 5) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { [weak self] in
                let status = await self?.reachable() ?? false
                self?.updateReachable(status)
            }
        }
    }
    
    private func updateReachable(_ isReachable: Bool) {
        DispatchQueue.main.async {
            withAnimation {
                self.isReachable = isReachable
            }
        }
    }

    private func stopCheckingReachability() {
        timer?.invalidate()
        timer = nil
    }

    /// Checks if any provider is reachable (Swama, Ollama, or Apple Foundation)
    private func reachable() async -> Bool {
        // Check providers sequentially to avoid Swift 6 concurrency issues
        let swamaReachable = await SwamaService.shared.reachable()
        if swamaReachable { return true }
        
        let ollamaReachable = await OllamaService.shared.reachable()
        if ollamaReachable { return true }
        
        let appleReachable = await AppleFoundationService.shared.reachable()
        return appleReachable
    }
    
    @MainActor func uiLog(message: String, status: NotificationMessage.Status) {
        notifications = [NotificationMessage(message: message, status: status)] + notifications.suffix(5)
    }
}

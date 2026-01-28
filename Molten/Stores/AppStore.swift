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
    /// Platform-specific default ping intervals:
    /// - macOS: 15 seconds (desktop, less battery concern)
    /// - iOS/iPadOS: 30 seconds (mobile, better battery life)
    private var pingInterval: TimeInterval = {
        #if os(macOS)
        return 15
        #else
        return 30
        #endif
    }()
    /// True when at least one provider (Swama, Ollama, or Apple Foundation) is reachable
    @MainActor var isReachable: Bool = true
    @MainActor var notifications: [NotificationMessage] = []
    @MainActor var menuBarIcon: String? = nil
    var appState: AppState = .chat
    
    // Caching and backoff for reachability checks
    private var lastReachabilityCheck: Date = .distantPast
    private var cachedReachabilityResult: Bool = true
    private var consecutiveFailures: Int = 0
    private let cacheTTL: TimeInterval = 10 // Cache results for 10 seconds
    private let maxBackoffInterval: TimeInterval = 60 // Max 60 seconds between checks when unreachable
    private let minCheckInterval: TimeInterval = 5 // Minimum 5 seconds between checks

    init() {
        let defaultInterval: TimeInterval = {
            #if os(macOS)
            return 15
            #else
            return 30
            #endif
        }()
        
        if let storedIntervalString = UserDefaults.standard.string(forKey: "pingInterval") {
            pingInterval = Double(storedIntervalString) ?? defaultInterval
            
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
        // Use a longer interval if we've had consecutive failures (exponential backoff)
        let effectiveInterval = calculateEffectiveInterval(baseInterval: interval)
        
        timer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                guard let self = self else { return }
                
                // Skip if we've checked recently (caching)
                let timeSinceLastCheck = Date().timeIntervalSince(self.lastReachabilityCheck)
                if timeSinceLastCheck < self.cacheTTL {
                    // Use cached result
                    await self.updateReachable(self.cachedReachabilityResult)
                    return
                }
                
                // Perform actual check
                let status = await self.reachable()
                await self.updateReachable(status)
                
                // Update cache and backoff state
                self.lastReachabilityCheck = Date()
                self.cachedReachabilityResult = status
                
                if status {
                    // Reset backoff on success
                    self.consecutiveFailures = 0
                    // Restart timer with normal interval if we were in backoff
                    if self.consecutiveFailures == 0 && effectiveInterval > interval {
                        self.stopCheckingReachability()
                        self.startCheckingReachability(interval: interval)
                    }
                } else {
                    // Increase backoff on failure
                    self.consecutiveFailures += 1
                    // Restart timer with longer interval if we've had multiple failures
                    if self.consecutiveFailures > 3 && effectiveInterval < self.maxBackoffInterval {
                        self.stopCheckingReachability()
                        self.startCheckingReachability(interval: interval)
                    }
                }
            }
        }
    }
    
    /// Calculate effective check interval based on consecutive failures (exponential backoff)
    /// Uses different strategies for default localhost vs user-configured URLs
    private func calculateEffectiveInterval(baseInterval: TimeInterval) -> TimeInterval {
        guard baseInterval > 0 && baseInterval < .infinity else { return baseInterval }
        
        if consecutiveFailures == 0 {
            return baseInterval
        }
        
        // Check if services are using default localhost (more aggressive backoff)
        let usingDefaults = OllamaService.shared.usingDefaultLocalhost || 
                           SwamaService.shared.usingDefaultLocalhost
        
        if usingDefaults {
            // Default localhost: More aggressive backoff since it's often not running
            // 30s → 60s → 120s → 240s → max 300s (5 min)
            let defaultBackoffBase: TimeInterval = 30
            let defaultMaxBackoff: TimeInterval = 300
            let backoffMultiplier = min(pow(2.0, Double(consecutiveFailures - 1)), defaultMaxBackoff / defaultBackoffBase)
            let effectiveInterval = defaultBackoffBase * max(1.0, backoffMultiplier)
            return min(effectiveInterval, defaultMaxBackoff)
        } else {
            // User-configured URL: Less aggressive backoff (user explicitly wants it checked)
            // 10s → 20s → 40s → max 60s
            let backoffMultiplier = min(pow(2.0, Double(consecutiveFailures)), maxBackoffInterval / baseInterval)
            let effectiveInterval = baseInterval * backoffMultiplier
            return min(effectiveInterval, maxBackoffInterval)
        }
    }
    
    private func updateReachable(_ isReachable: Bool) async {
        await MainActor.run {
            withAnimation {
                self.isReachable = isReachable
            }
        }
    }

    private func stopCheckingReachability() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Force an immediate reachability check (bypasses cache)
    /// Useful when user changes settings or manually triggers a check
    func forceReachabilityCheck() {
        Task {
            let status = await reachable()
            await updateReachable(status)
            lastReachabilityCheck = Date()
            cachedReachabilityResult = status
            if status {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
            }
        }
    }

    /// Checks if any provider is reachable (Swama, Ollama, or Apple Foundation)
    /// Services already have timeouts, but we check sequentially to avoid multiple simultaneous requests
    private func reachable() async -> Bool {
        // Check providers sequentially to avoid Swift 6 concurrency issues
        // Apple Foundation is always available if the framework is present, so check it first (no network)
        let appleReachable = await AppleFoundationService.shared.reachable()
        if appleReachable { return true }
        
        // Check Swama (has 2s timeout built-in)
        let swamaReachable = await SwamaService.shared.reachable()
        if swamaReachable { return true }
        
        // Check Ollama (OllamaKit has its own timeout)
        let ollamaReachable = await OllamaService.shared.reachable()
        return ollamaReachable
    }
    
    @MainActor func uiLog(message: String, status: NotificationMessage.Status) {
        notifications = [NotificationMessage(message: message, status: status)] + notifications.suffix(5)
    }
}

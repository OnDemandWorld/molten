//
//  MoltenApp.swift
//  Molten
//
//  Main application entry point for Molten.
//  Configures the app window, keyboard shortcuts, and menu bar integration.
//
//  Key Features:
//  - Window management and panel mode
//  - Keyboard shortcuts (⌘⌥K for panel toggle)
//  - Menu bar integration (optional)
//  - Platform-specific configurations
//
//  Created by Augustinas Malinauskas on 09/12/2023.
//  Refactored for Molten v1.0.0
//

import SwiftUI
import SwiftData

#if os(macOS)
import KeyboardShortcuts
extension KeyboardShortcuts.Name {
    static let togglePanelMode = Self("togglePanelMode1", default: .init(.k, modifiers: [.command, .option]))
}
#endif

@main
struct MoltenApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(PanelManager.self) var panelManager
#endif

    init() {
        #if os(iOS)
        // K-P6: BGTaskScheduler handlers must be registered before the end
        // of application(_:didFinishLaunching…) — App.init is the SwiftUI
        // equivalent. Registering later (e.g. in a view .task) misses
        // background launches, so the system never runs the handler.
        KnowledgeBackgroundTask.register()
        #endif

        // G2 (review 2026-11-24): a mid-session tier change must re-resolve
        // the Knowledge root and start/stop sync — not wait for relaunch.
        // The handler is idempotent (same work as the launch flow).
        NotificationCenter.default.addObserver(
            forName: EntitlementManager.tierDidChangeNotification,
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await KnowledgeSync.shared.refreshForEntitlementChange()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ApplicationEntry()
#if os(macOS)
                .onKeyboardShortcut(KeyboardShortcuts.Name.togglePanelMode, type: .keyDown) {
                    panelManager.togglePanel()
                }
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
#endif
        }
#if os(macOS)
        .commands {
            Menus()
        }
#endif
#if os(macOS)
        Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
            KeyboardShortcutsDemo()
        }
#endif
    }
}


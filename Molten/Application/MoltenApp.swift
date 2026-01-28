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
    @State private var appStore = AppStore.shared
#if os(macOS)
    @NSApplicationDelegateAdaptor(PanelManager.self) var panelManager
#endif
    
    var body: some Scene {
        WindowGroup {
            ApplicationEntry()
#if os(macOS)
                .onGlobalKeyboardShortcut(KeyboardShortcuts.Name.togglePanelMode, type: .keyDown) {
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
        
#if os(macOS)
#if false
        MenuBarExtra {
            MenuBarControl()
        } label: {
            if let iconName = appStore.menuBarIcon {
                Image(systemName: iconName)
            } else {
                MenuBarControlView.icon
            }
        }
        .menuBarExtraStyle(.window)
#endif
#endif
    }
}


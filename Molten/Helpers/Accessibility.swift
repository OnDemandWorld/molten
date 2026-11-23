//
//  Accessibility.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 29/02/2024.
//

#if os(macOS)
import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

final class Accessibility {
    nonisolated(unsafe) static let shared = Accessibility()

    /// Check if Molten has the right permissions
    func checkAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false, ]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func showAccessibilityInstructionsWindow() {
        if checkAccessibility() {
            return
        }
        
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Async so the copy fallback's wait never blocks the main actor
    /// (review 2026-11-24: togglePanel called this synchronously on main).
    func getSelectedText() async -> String? {
        if let text = getSelectedTextAX(), text.count > 1  {
            return text
        }

        return await getSelectedTextViaCopy()
    }
    
    func getSelectedTextAX() -> String? {
        let systemWideElement = AXUIElementCreateSystemWide()
        
        var focusedApp: AnyObject?
        var error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard error == .success, let focusedAppElement = focusedApp as! AXUIElement? else { return nil }
        
        var focusedUIElement: AnyObject?
        error = AXUIElementCopyAttributeValue(focusedAppElement, kAXFocusedUIElementAttribute as CFString, &focusedUIElement)
        guard error == .success, let focusedElement = focusedUIElement as! AXUIElement? else { return nil }
        
        var selectedTextValue: AnyObject?
        error = AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        guard error == .success, let selectedText = selectedTextValue as? String else { return nil }
        
        return selectedText
    }
    
    
    func getSelectedTextViaCopy(retryAttempts: Int = 1) async -> String? {
        let pasteboard = NSPasteboard.general
        // Snapshot ALL types of every item — restoring only .string values
        // destroyed image/file/multi-item clipboards (review 2026-11-24).
        let originalItems: [NSPasteboardItem] = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
        pasteboard.clearContents()
        var attempts = 0
        var newContent: String?

        while attempts < retryAttempts && newContent == nil {
            simulateCopyKeyPress()
            try? await Task.sleep(nanoseconds: 100_000_000)

            newContent = pasteboard.string(forType: .string)
            if let newContent = newContent, !newContent.isEmpty {
                break
            } else {
                newContent = nil
            }
            attempts += 1
        }

        // Always restore the user's clipboard — the copied selection must
        // not clobber it, even on success.
        pasteboard.clearContents()
        if !originalItems.isEmpty {
            pasteboard.writeObjects(originalItems)
        }

        return newContent
    }
    
    func simulateCopyKeyPress() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Define the virtual keycode for 'C' and the command modifier
        let commandKey = CGEventFlags.maskCommand.rawValue
        let cKeyCode = CGKeyCode(8)  // Virtual keycode for 'C'
        
        // Create and post a key down event
        if let commandCDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true) {
            commandCDown.flags = CGEventFlags(rawValue: commandKey)
            commandCDown.post(tap: .cghidEventTap)
        }
        
        // Create and post a key up event
        if let commandCUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false) {
            commandCUp.flags = CGEventFlags(rawValue: commandKey)
            commandCUp.post(tap: .cghidEventTap)
        }
    }
    
    
    func simulateTyping(for string: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(string.utf16)
        
        utf16Chars.forEach { uniChar in
            var uniChar = uniChar
            if uniChar == 0x000A {
                
                if let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x38), keyDown: true) {
                    shiftDown.post(tap: .cghidEventTap)
                }
                
                // Simulate pressing and releasing the Return key
                if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x24), keyDown: true),
                   let eventUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x24), keyDown: false) {
                    
                    eventDown.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.005)
                    eventUp.post(tap: .cghidEventTap)
                }
                
                // Simulate releasing the Shift key
                if let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0x38), keyDown: false) {
                    shiftUp.post(tap: .cghidEventTap)
                }
                
            } else {
                // Handle other characters as before
                if let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                   let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                    
                    eventDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
                    eventUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
                    
                    eventDown.post(tap: .cghidEventTap)
                    Thread.sleep(forTimeInterval: 0.005)
                    eventUp.post(tap: .cghidEventTap)
                }
            }
        }
    }
    
    static func simulatePasteCommand() {
        let commandKey = CGEventFlags.maskCommand.rawValue
        let vKeyCode = 0x09
        let source = CGEventSource(stateID: .hidSystemState)
        if let commandVDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKeyCode), keyDown: true) {
            commandVDown.flags = CGEventFlags(rawValue: commandKey)
            commandVDown.post(tap: .cghidEventTap)
        }
        
        usleep(50000)
        
        if let commandVUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(vKeyCode), keyDown: false) {
            commandVUp.flags = CGEventFlags(rawValue: commandKey)
            commandVUp.post(tap: .cghidEventTap)
        }
    }
    
    
}
#endif

//
//  PanelManager.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 12/02/2024.
//

#if os(macOS)
import SwiftUI
import Carbon
import AsyncAlgorithms

final actor Printer {
    func write(_ message: String) async {
        Clipboard.shared.setString(message)
        // Task.sleep, not usleep: blocking an actor thread stalls a
        // cooperative-pool thread for every paste tick (review 2026-11-24).
        try? await Task.sleep(nanoseconds: 50_000_000)
        Accessibility.simulatePasteCommand()
    }
}

class PanelManager: NSObject, NSApplicationDelegate {
    var targetApplication: NSRunningApplication?
    var lastPrintApplication: NSRunningApplication?
    var panel: FloatingPanel!
    var completionsPanelVM = CompletionsPanelVM()
    @MainActor var allowPrinting = true
    let printer = Printer()
    
    override init() {
        super.init()
        
        Task {
            await NSApp.setActivationPolicy(.regular)
            await NSApp.activate(ignoringOtherApps: true)
            await handleNewMessages()
        }
    }
    
    private func handleNewMessages() async {
        let timer = AsyncTimerSequence(interval: .seconds(0.1), clock: .continuous)
        for await _ in timer {
            // If user focused different application stop writing
            if lastPrintApplication != nil && lastPrintApplication?.localizedName != NSWorkspace.shared.runningApplications.first(where: {$0.isActive})?.localizedName {
                // dequeue all and stop execution
                await completionsPanelVM.cancel()
                _ = await completionsPanelVM.sentenceQueue.dequeueAll()
                lastPrintApplication = nil
                continue
            }
            
            // hold printing until user action and ensuring that your driving experience
            if await !allowPrinting {
                continue
            }
            
            let sentencesToConsume = await completionsPanelVM.sentenceQueue.dequeueAll().joined()
            
            if sentencesToConsume.isEmpty {
                continue
            }
            
            lastPrintApplication = NSWorkspace.shared.runningApplications.first{$0.isActive}
            await printer.write(sentencesToConsume)
        }
    }
    
    
    @MainActor
    @objc func togglePanel() {
        let accessibilityStatus = Accessibility.shared.checkAccessibility()
        if !accessibilityStatus {
            Accessibility.shared.showAccessibilityInstructionsWindow()
        }
        
        targetApplication = NSWorkspace.shared.runningApplications.first{$0.isActive}

        Task {
            // Await off-main: the copy fallback sleeps and posts events;
            // running it synchronously blocked the UI (review 2026-11-24).
            completionsPanelVM.selectedText = await Accessibility.shared.getSelectedText()

            if panel == nil || !panel.isVisible {
                showPanel()
                
                // subscribe to keybaord event to avoid beep
//                HotkeyService.shared.registerSingleUseEscape(modifiers: []) { [weak self] in
//                    self?.hidePanel()
//                }
                
                return
            }
            
            hidePanel()
        }
    }
    
    @MainActor
    @objc func hidePanel() {
        panel.orderOut(nil)
    }
    
    @MainActor
    @objc func showPanel() {
        // Reuse the panel instead of recreating it on every show — the old
        // instance was never closed (review 2026-11-24).
        if panel == nil {
            createPanel()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @MainActor
    @objc func onSubmitMessage() {
        UpsellCoordinator.shared.noteEvent(.panelUse)
        allowPrinting = true
        hidePanel()
        
        /// Focus Molten
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).first {
            app.activate(options: [.activateAllWindows])
            
            NSApp.windows.forEach { window in
                if window.isMiniaturized {
                    window.deminiaturize(nil)
                }
            }
        }
    }
    
    @MainActor
    @objc func onSubmitCompletion(scheduledTyping: Bool) {
        UpsellCoordinator.shared.noteEvent(.panelUse)
        allowPrinting = true
        
        if scheduledTyping {
            self.allowPrinting = false
            HotkeyService.shared.registerSingleUseSpace(modifiers: []) { [weak self] in
                self?.allowPrinting = true
                self?.hidePanel()
            }
        } else {
            hidePanel()
        }
        targetApplication?.activate()
    }
    
    @MainActor
    func createPanel() {
        // Weak captures: the hosting view's rootView closures otherwise
        // retain PanelManager, which retains the panel → cycle
        // (review 2026-11-24).
        let contentView = PromptPanel(
            completionsPanelVM: completionsPanelVM,
            onSubmitPanel: { [weak self] in self?.onSubmitMessage() },
            onSubmitCompletion: { [weak self] scheduled in
                self?.onSubmitCompletion(scheduledTyping: scheduled)
            },
            onLayoutUpdate: { [weak self] in self?.updatePanelSizeIfNeeded() }
        )
        let hostingView = NSHostingView(rootView: contentView)
        let idealSize = hostingView.fittingSize

        panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: idealSize.width, height: idealSize.height),
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.center()
        panel.orderFront(nil)
    }
    
    @MainActor func updatePanelSizeIfNeeded() {
        guard let hostingView = panel.contentView as? NSHostingView<PromptPanel> else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            let newSize = hostingView.fittingSize
            
            if newSize == .zero {
                return
            }
            
            if strongSelf.panel.frame.size != newSize {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    
                    // Calculate the difference in height
                    let heightDifference = newSize.height - strongSelf.panel.frame.size.height
                    
                    // Adjust the y position to keep the bottom edge constant
                    let newY = strongSelf.panel.frame.origin.y - heightDifference
                    
                    strongSelf.panel.animator().setFrame(
                        NSRect(x: strongSelf.panel.frame.origin.x,
                               y: newY, // Use the new Y
                               width: newSize.width,
                               height: newSize.height),
                        display: true)
                }, completionHandler: {})
            }
        }
    }
}

extension PanelManager {
    @MainActor func windowDidResignKey(_ notification: Notification) {
        if let panel = notification.object as? FloatingPanel, panel == self.panel {
            // Hide, don't close: the instance is reused on the next show.
            panel.orderOut(nil)
        }
    }
}
#endif

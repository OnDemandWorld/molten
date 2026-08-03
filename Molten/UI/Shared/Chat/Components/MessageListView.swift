//
//  MessageListVIew.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct MessageListView: View {
    var messages: [MessageSD]
    var conversationState: ConversationState
    var userInitials: String
    @Binding var editMessage: MessageSD?
    @State private var messageSelected: MessageSD?
    @StateObject private var speechSynthesizer = SpeechSynthesizer.shared
    @State private var scrollThrottleCounter: Int = 0

    // Track for auto-scroll during streaming
    private var isStreaming: Bool {
        conversationState == .loading && !(messages.last?.done ?? true)
    }

    private var currentContentLength: Int {
        messages.last?.content.count ?? 0
    }
    
    func onEditMessageTap() -> (MessageSD) -> Void {
        return { message in
            editMessage = message
        }
    }
    
    func onReadAloud(_ message: String) {
        Task {
            await speechSynthesizer.speak(text: message)
        }
    }
    
    func stopReadingAloud() {
        Task {
            await speechSynthesizer.stopSpeaking()
        }
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack {
                        ForEach(messages) { message in
                            let contextMenu = ContextMenu(menuItems: {
                                Button(action: {Clipboard.shared.setString(message.content)}) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                
#if os(iOS) || os(visionOS)
                                Button(action: { messageSelected = message }) {
                                    Label("Select Text", systemImage: "selection.pin.in.out")
                                }
                                
                                Button(action: {
                                    onReadAloud(message.content)
                                }) {
                                    Label("Read Aloud", systemImage: "speaker.wave.3.fill")
                                }
#endif
                                
                                if message.role == "user" {
                                    Button(action: {
                                        withAnimation { editMessage = message }
                                    }) {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                }
                                
                                if editMessage?.id == message.id {
                                    Button(action: {
                                        withAnimation { editMessage = nil }
                                    }) {
                                        Label("Unselect", systemImage: "pencil")
                                    }
                                }
                            })
                            
                            ChatMessageView(
                                message: message,
                                isStreaming: conversationState == .loading && messages.last == message && !message.done,
                                userInitials: userInitials,
                                editMessage: $editMessage
                            )
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                            .contextMenu(contextMenu)
                            .runningBorder(animated: message.id == editMessage?.id)
                            .id(message.id)
                        }
                    }
                }
                .onAppear {
                    scrollViewProxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
                // Scroll when new message is added
                .onChange(of: messages.last?.id) { _, newId in
                    if newId != nil {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollViewProxy.scrollTo(newId, anchor: .bottom)
                        }
                    }
                }
                // Scroll during streaming - use a counter to trigger on content changes
                // This is more reliable than observing content length directly
                .onChange(of: currentContentLength) { oldValue, newValue in
                    guard isStreaming && newValue > oldValue else { return }
                    // Scroll every content update during streaming (throttled by SwiftUI)
                    withAnimation(.easeOut(duration: 0.1)) {
                        scrollViewProxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                // Scroll when message completes streaming (done flag changes)
                .onChange(of: messages.last?.done) { _, done in
                    if done == true {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollViewProxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }
#if os(iOS) || os(visionOS)
                .sheet(item: $messageSelected) { message in
                    SelectTextSheet(message: message)
                }
#endif
            }
            
            ReadingAloudView(onStopTap: stopReadingAloud)
                .frame(maxWidth: 400)
                .showIf(speechSynthesizer.isSpeaking)
                .transition(.asymmetric(
                    insertion: AnyTransition.opacity.combined(with: .scale(scale: 0.7, anchor: .top)),
                    removal: AnyTransition.opacity.combined(with: .scale(scale: 0.7, anchor: .top)))
                )
        }
    }
}

#Preview {
    MessageListView(
        messages: MessageSD.sample,
        conversationState: .loading,
        userInitials: "AM",
        editMessage: .constant(MessageSD.sample[0])
    )
}

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
    /// Monotonic flush counter from ConversationStore — the auto-scroll
    /// trigger during streaming (cheap Int change signal, no row re-diff).
    var streamTickCount: Int
    @Binding var editMessage: MessageSD?
    @State private var messageSelected: MessageSD?
    @StateObject private var speechSynthesizer = SpeechSynthesizer.shared

    // Track for auto-scroll during streaming
    private var isStreaming: Bool {
        conversationState == .loading && !(messages.last?.done ?? true)
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
                    // Lazy so long conversations don't build every Markdown
                    // row up front. Initial bottom position is handled by
                    // defaultScrollAnchor below (scrollTo can't target rows
                    // that don't exist yet in a lazy container).
                    LazyVStack {
                        ForEach(messages) { message in
                            let contextMenu = ContextMenu(menuItems: {
                                Button(action: {Clipboard.shared.setString(message.content)}) {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                
#if os(iOS)
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
                            // Skip body re-evaluation (Markdown re-parsing)
                            // for rows whose inputs didn't change — during
                            // streaming that's every row except the last.
                            // Direct @Model observation still updates rows
                            // whose own properties change.
                            .equatable()
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
                // Open pinned to the bottom without needing the last row to
                // exist yet (LazyVStack + scrollTo would silently no-op).
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    scrollViewProxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
                // Scroll when new message is added
                .onChange(of: messages.last?.id) { _, newId in
                    guard let newId else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollViewProxy.scrollTo(newId, anchor: .bottom)
                    }
                    // In a lazy container the new row may not be rendered
                    // yet, making the call above a no-op. Retry once the
                    // layout pass has had a chance to instantiate it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollViewProxy.scrollTo(newId, anchor: .bottom)
                        }
                    }
                }
                // Follow streamed content: the store bumps streamTickCount on
                // every throttled flush (explicit signal — no dependence on
                // observing the last row's content length from this body).
                .onChange(of: streamTickCount) {
                    guard isStreaming else { return }
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
                .scrollDismissesKeyboard(.interactively)
#if os(iOS)
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
        streamTickCount: 0,
        editMessage: .constant(MessageSD.sample[0])
    )
}

//
//  SidebarView.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import SwiftUI

struct SidebarView: View {
    @Environment(\.openWindow) var openWindow
    var selectedConversation: ConversationSD?
    var conversations: [ConversationSD]
    var onConversationTap: (_ conversation: ConversationSD) -> ()
    var onConversationDelete: (_ conversation: ConversationSD) -> ()
    var onDeleteDailyConversations: (_ date: Date) -> ()
    @State var showSettings = false
    @State var showCompletions = false
    @State var showKeyboardShortcutas = false
    
    private func onSettingsTap() {
        Task {
            showSettings.toggle()
            Haptics.shared.mediumTap()
        }
    }
    
    // C1: full-text search across all conversations.
    @State private var searchText = ""
    @State private var searchHits: [ConversationSearchHit] = []

    var body: some View {
        VStack {
            TextField("Search conversations", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: searchText) { _, query in
                    searchHits = query.isEmpty ? [] : ConversationSearch.shared.search(query)
                }
            if !searchHits.isEmpty {
                List(searchHits) { hit in
                    Button {
                        if let conversation = conversations.first(where: { $0.id == hit.conversationID }) {
                            onConversationTap(conversation)
                            searchText = ""
                            searchHits = []
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(hit.conversationName).font(.caption.bold())
                            Text(hit.snippet).font(.caption2).lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxHeight: 200)
            }
            ScrollView() {
                ConversationHistoryList(
                    selectedConversation: selectedConversation,
                    conversations: conversations,
                    onTap: onConversationTap,
                    onDelete: onConversationDelete,
                    onDeleteDailyConversations: onDeleteDailyConversations
                )
            }
            .scrollIndicators(.never)

            // Molten 2.0 — K-U1: Knowledge bases.
            KnowledgeSidebar()

            Divider()
            
#if os(macOS)
            SidebarButton(title: "Completions", image: "textformat.abc", onClick: {showCompletions.toggle()})
            
            SidebarButton(title: "Shortcuts", image: "keyboard.fill", onClick: {showKeyboardShortcutas.toggle()})
#endif
            
            SidebarButton(title: "Settings", image: "gearshape.fill", onClick: onSettingsTap)
            
        }
        .padding()
#if os(macOS)
        .focusedSceneValue(\.showSettings, $showSettings)
#endif
        .sheet(isPresented: $showSettings) {
            Settings()
        }
#if os(macOS)
        .sheet(isPresented: $showCompletions) {
            CompletionsEditor()
        }
        .sheet(isPresented: $showKeyboardShortcutas) {
            KeyboardShortcutsDemo()
        }
#endif
        
    }
}

#Preview {
    SidebarView(selectedConversation: ConversationSD.sample[0], conversations: ConversationSD.sample, onConversationTap: {_ in}, onConversationDelete: {_ in}, onDeleteDailyConversations: {_ in})
}

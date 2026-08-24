//
//  EmptyConversationView.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 10/02/2024.
//

import SwiftUI

struct EmptyConversationView: View, KeyboardReadable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var showPromptsAnimation = false
    @State var prompts: [SamplePrompts] = []
    var sendPrompt: (String) -> ()
#if os(iOS)
    @State var isKeyboardVisible = false
#endif

#if os(macOS)
    var columns = Array.init(repeating: GridItem(.flexible(), spacing: 15), count: 4)
#else
    var columns = [GridItem(.flexible()), GridItem(.flexible())]
#endif
    @State var visibleItems = Set<Int>()
    /// On-device personalized starters (empty until generation succeeds).
    @State private var suggestions = PromptSuggestionsStore.shared
    /// Whether the cards currently shown already include generated prompts —
    /// used to avoid swapping cards under the user's pointer.
    @State private var currentMixHasGenerated = false

    /// Builds the card mix: generated prompts (when available) plus static
    /// samples, so the grid is never empty.
    private func reloadPrompts() {
        let mix = suggestions.mixPrompts()
        prompts = mix
        let generatedTexts = Set(suggestions.generated.map(\.prompt))
        currentMixHasGenerated = mix.contains { generatedTexts.contains($0.prompt) }
    }

    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 25) {
                VStack(alignment: .center) {
                    Text("Molten")
                        .font(Font.system(size: 46, weight: .medium, design: .rounded))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .moltenifyGlow()
                }
                
                LazyVGrid(columns: columns, alignment: .leading, spacing: 15) {
                    ForEach(0..<prompts.prefix(4).count, id: \.self) { index in
                        Button(action: {
                            withAnimation {
                                sendPrompt(prompts[index].prompt)
                            }
                        }) {
                            VStack(alignment: .leading) {
                                Text(prompts[index].prompt)
                                    .font(.system(size: 15))
                                Spacer()
                                
                                HStack {
                                    Spacer()
                                    Image(systemName: prompts[index].type.icon)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(15)
                            .background(Color.gray5Custom)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            
                        }
                        .opacity(visibleItems.contains(index) ? 1 : 0)
                        // Reduce Motion (F-32): no staggered entrance.
                        .animation(.easeIn(duration: reduceMotion ? 0 : 0.3).delay(reduceMotion ? 0 : 0.2 * Double(index)), value: visibleItems)
                        .transition(.slide)
                        .showIf(showPromptsAnimation)
                        .buttonStyle(.plain)
                    }
                }
                .onAppear {
                    for index in 0..<4 {
                        DispatchQueue.main.async {
                            visibleItems.insert(index)
                        }
                    }
                }
                .frame(maxWidth: 700)
                .padding()
                .transition(AnyTransition(.opacity).combined(with: .slide))
#if os(iOS)
                .showIf(!isKeyboardVisible)
#endif
            }
            Spacer()
        }
        .onAppear {
            DispatchQueue.main.async {
                withAnimation {
                    reloadPrompts()
                    showPromptsAnimation = true
                }
            }
            // Personalized starters generate in the background; the page is
            // already showing the static pool by now, so it never blocks.
            suggestions.refreshIfNeeded()
        }
        .onChange(of: suggestions.generated) { _, _ in
            // Swap in personalized cards only while a purely static mix is
            // showing; once generated prompts are visible, keep cards stable.
            if !currentMixHasGenerated {
                withAnimation {
                    reloadPrompts()
                }
            }
        }
#if os(iOS)
        .onReceive(keyboardPublisher) { newIsKeyboardVisible in
            DispatchQueue.main.async {
                withAnimation {
                    isKeyboardVisible = newIsKeyboardVisible
                }
            }
        }
#endif
        
    }
}

#Preview(traits: .fixedLayout(width: 1000, height: 1000)) {
    EmptyConversationView(sendPrompt: {_ in})
}

//
//  ModelSelector.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 11/12/2023.
//

import SwiftUI

struct ModelSelectorView: View {
    var modelsList: [LanguageModelSD]
    var selectedModel: LanguageModelSD?
    var onSelectModel: @MainActor (_ model: LanguageModelSD?) -> ()
    var showChevron = true
    
    var body: some View {
        Menu {
            ForEach(modelsList, id: \.self) { model in
                Button(action: {
                    withAnimation(.easeOut) {    
                        onSelectModel(model)
                    }
                }) {
                    Text(model.displayName)
                        .font(.body)
                        .tag(model.name)
                }
            }
        } label: {
            HStack(alignment: .center) {
                if let selectedModel = selectedModel {
                    HStack(alignment: .bottom, spacing: 5) {

                        #if os(macOS)
                        Text(selectedModel.displayName)
                            .font(.body)
                        #elseif os(iOS)
                        Text(selectedModel.displayName)
                            .font(.body)
                            .foregroundColor(Color.labelCustom)
                        #endif
                    }
                } else {
                    // Placeholder keeps the menu a real tap target even
                    // before a model is selected (a bare 10pt chevron was
                    // effectively untappable).
                    Text("Select model")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10)
                    .foregroundColor(Color(.label))
                    .showIf(showChevron)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Select model")
        }
    }
}

#Preview {
    ModelSelectorView(
        modelsList: LanguageModelSD.sample,
        selectedModel: LanguageModelSD.sample[0], 
        onSelectModel: {_ in},
        showChevron: false
    )
}

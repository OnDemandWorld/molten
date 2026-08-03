//
//  ConversationStatusView.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 10/12/2023.
//

import SwiftUI
import ActivityIndicatorView

struct ConversationStatusView: View {
    var state: ConversationState
    /// Called when the user dismisses the error banner (F-35).
    var onDismiss: () -> Void = {}

    var body: some View {
        switch state {
        case .loading: EmptyView()
        case .completed: EmptyView()
        case .error(let message):
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text(message)
                        .foregroundColor(.red)
                        .font(.system(size: 16))
                    Spacer()
                }
                // VoiceOver reads the message as one element.
                .accessibilityElement(children: .combine)

                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }
        }
    }
}

#Preview {
    Group {
        ConversationStatusView(state: .loading)
        ConversationStatusView(state: .completed)
        ConversationStatusView(state: .error(message: "Could not connect"))
    }
}

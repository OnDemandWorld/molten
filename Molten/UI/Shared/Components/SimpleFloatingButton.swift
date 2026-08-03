//
//  SimpleFloatingButton.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 18/02/2024.
//

import SwiftUI

struct SimpleFloatingButton: View {
    var systemImage: String
    var onClick: () -> ()
    /// VoiceOver label; falls back to the symbol name if unset.
    var accessibilityTitle: String? = nil

    var body: some View {
        Button(action: onClick) {
            Image(systemName: systemImage)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundColor(Color.label)
                .frame(height: 18)
                // Comfortable hit target without enlarging the glyph (F-31).
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(GrowingButton())
        .contentShape(Rectangle())
        .accessibilityLabel(Text(accessibilityTitle ?? systemImage))
    }
}

#Preview {
    SimpleFloatingButton(systemImage: "photo.fill", onClick: {})
        .frame(width: 100, height: 100)
}

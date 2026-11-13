//
//  ContextRing.swift
//  Molten
//
//  Molten 2.0 — M6, X1. Composer ring: estimated tokens vs the model's
//  context window. Warns at 80% (orange) and 95% (red).
//

import SwiftUI

struct ContextRing: View {
    let used: Int
    let window: Int

    private var fraction: Double {
        ContextWindow.usageFraction(used: used, window: window)
    }

    private var color: Color {
        if fraction >= ContextWindow.criticalThreshold { return .red }
        if fraction >= ContextWindow.warningThreshold { return .orange }
        return .accentColor
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 22, height: 22)
        .accessibilityLabel("Context usage \(Int(fraction * 100)) percent")
        .help("\(used) / \(window) tokens (estimated)")
    }
}

/// Loads the window for the selected model and estimates current usage.
struct ContextRingForModel: View {
    let model: LanguageModelSD?
    let text: String
    @State private var window = ContextWindow.defaultWindow

    var body: some View {
        ContextRing(used: TokenEstimator.estimate(text), window: window)
            .task(id: model?.name) {
                if let model {
                    window = await ContextWindow.window(for: model)
                }
            }
    }
}

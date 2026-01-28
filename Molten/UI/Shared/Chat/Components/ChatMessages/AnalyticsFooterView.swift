//
//  AnalyticsFooterView.swift
//  Molten
//
//  Displays performance analytics below each assistant message.
//  Shows prompt eval rate, eval rate, overall throughput, total tokens, and total time.
//
//  Metrics Displayed:
//  - Prompt Eval Rate: How fast the model processes input (tokens/s)
//  - Eval Rate: How fast the model generates output (tokens/s)
//  - Overall Throughput: Total tokens per second (total tokens / total time)
//  - Total Tokens: Sum of prompt and completion tokens
//  - Total Time: End-to-end response time
//
//  Created for Molten v1.0.0
//

import SwiftUI

struct AnalyticsFooterView: View {
    let message: MessageSD
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }
    
    private var promptEvalRate: String? {
        guard let promptTokens = message.promptTokens,
              let promptEvalTime = message.promptEvalTime else {
            return nil
        }
        // Handle case where promptEvalTime is 0 or very small (shouldn't happen, but be safe)
        guard promptEvalTime > 0.001 else {
            return nil
        }
        let rate = Double(promptTokens) / promptEvalTime
        return String(format: "%.1f", rate)
    }
    
    private var evalRate: String? {
        guard let completionTokens = message.completionTokens,
              let evalTime = message.evalTime,
              evalTime > 0 else {
            return nil
        }
        let rate = Double(completionTokens) / evalTime
        return String(format: "%.1f", rate)
    }
    
    private var totalTokens: String? {
        if let total = message.totalTokens {
            return "\(total)"
        } else if let prompt = message.promptTokens, let completion = message.completionTokens {
            return "\(prompt + completion)"
        }
        return nil
    }
    
    private var totalTime: String? {
        guard let time = message.totalTime, time > 0 else { return nil }
        if time < 1.0 {
            return String(format: "%.0fms", time * 1000)
        } else {
            return String(format: "%.1fs", time)
        }
    }
    
    private var overallThroughput: String? {
        guard let totalTokens = message.totalTokens ?? (message.promptTokens != nil && message.completionTokens != nil ? (message.promptTokens! + message.completionTokens!) : nil),
              let totalTime = message.totalTime,
              totalTime > 0 else {
            return nil
        }
        let rate = Double(totalTokens) / totalTime
        return String(format: "%.1f", rate)
    }
    
    // MARK: - Compact Layout (iPhone)
    
    @ViewBuilder
    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            // First row: eval rates
            HStack(spacing: 16) {
                if let promptRate = promptEvalRate {
                    analyticsItem(label: "prompt", value: "\(promptRate) t/s")
                }
                if let evalRate = evalRate {
                    analyticsItem(label: "eval", value: "\(evalRate) t/s")
                }
                if let throughput = overallThroughput {
                    analyticsItem(label: "overall", value: "\(throughput) t/s")
                }
            }
            
            // Second row: totals
            HStack(spacing: 16) {
                if let tokens = totalTokens {
                    analyticsItem(label: "tokens", value: tokens)
                }
                if let time = totalTime {
                    analyticsItem(label: "time", value: time)
                }
            }
        }
    }
    
    // MARK: - Regular Layout (iPad/Mac)
    
    @ViewBuilder
    private var regularLayout: some View {
        HStack(spacing: 16) {
            if let promptRate = promptEvalRate {
                analyticsItem(label: "prompt eval", value: "\(promptRate) t/s")
            }
            if let evalRate = evalRate {
                analyticsItem(label: "eval rate", value: "\(evalRate) t/s")
            }
            
            Spacer()
            
            if let throughput = overallThroughput {
                analyticsItem(label: "overall", value: "\(throughput) t/s")
            }
            if let tokens = totalTokens {
                analyticsItem(label: "tokens", value: tokens)
            }
            if let time = totalTime {
                analyticsItem(label: "time", value: time)
            }
        }
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func analyticsItem(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
        }
    }
    
    var body: some View {
        if message.role == "assistant" && message.done {
            Group {
                if isCompact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    VStack {
        AnalyticsFooterView(message: MessageSD.sample[1])
    }
    .padding()
}


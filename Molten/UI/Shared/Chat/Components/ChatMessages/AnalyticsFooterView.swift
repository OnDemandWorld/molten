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
        return String(format: "%.2f", rate)
    }
    
    private var evalRate: String? {
        guard let completionTokens = message.completionTokens,
              let evalTime = message.evalTime,
              evalTime > 0 else {
            return nil
        }
        let rate = Double(completionTokens) / evalTime
        return String(format: "%.2f", rate)
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
            return String(format: "%.2fs", time)
        }
    }
    
    private var overallThroughput: String? {
        guard let totalTokens = message.totalTokens ?? (message.promptTokens != nil && message.completionTokens != nil ? (message.promptTokens! + message.completionTokens!) : nil),
              let totalTime = message.totalTime,
              totalTime > 0 else {
            return nil
        }
        let rate = Double(totalTokens) / totalTime
        return String(format: "%.2f", rate)
    }
    
    var body: some View {
        if message.role == "assistant" && message.done {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    // Prompt eval rate - show first if available
                    if let promptRate = promptEvalRate {
                        HStack(spacing: 4) {
                            Text("prompt eval rate:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(promptRate) tokens/s")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // Eval rate - show second if available
                    if let evalRate = evalRate {
                        HStack(spacing: 4) {
                            Text("eval rate:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(evalRate) tokens/s")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    Spacer()
                    
                    // Overall throughput - show if available
                    if let throughput = overallThroughput {
                        HStack(spacing: 4) {
                            Text("overall:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(throughput) tokens/s")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // Total tokens - show if available
                    if let tokens = totalTokens {
                        HStack(spacing: 4) {
                            Text("total tokens:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(tokens)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
                    
                    // Total time - show if available
                    if let time = totalTime {
                        HStack(spacing: 4) {
                            Text("total time:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(time)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                        }
                    }
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


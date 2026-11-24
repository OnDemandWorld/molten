//
//  SwiftUIView.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 18/12/2023.
//

import SwiftUI
import AVFoundation

struct RecordingView: View {
    @StateObject var speechRecognizer: SpeechRecognizer = SpeechRecognizer()
    @Binding var isRecording: Bool
    var onComplete: (_ transcription: String) -> () = {_ in}
    
    private func toggleRecord() {
        Task {
            await speechRecognizer.userInit()
            await toggleTranscribing()
        }
        Haptics.shared.mediumTap()
    }
    
    private func toggleTranscribing() async {
        if isRecording {
            speechRecognizer.stopTranscribing()
            // Never hand the "<< error >>" sentinel to the caller as if it
            // were the user's words (review 2026-11-24).
            let transcript = speechRecognizer.transcript
            if !(transcript.hasPrefix("<<") && transcript.hasSuffix(">>")) {
                onComplete(transcript)
            }
            isRecording = false
        } else {
            speechRecognizer.resetTranscript()
            let onCompleteClosure = onComplete
            speechRecognizer.startTranscribing(onUpdate: { @Sendable message in
                onCompleteClosure(message)
            })
            isRecording = true
        }
    }
    
    var body: some View {
        Button(action: toggleRecord) {
            Group {
                if isRecording {
                    ZStack {
                        Color(.systemBlue)

                        Image(systemName: "square.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.white)
                            .frame(width: 8)
                    }
                    .clipShape(Circle())
                    .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "waveform")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 20)
                        .foregroundStyle(Color(.systemGray))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(isRecording ? "Stop recording" : "Start voice input")
        .onChange(of: isRecording) { oldValue, newValue in
            if newValue == false {
                speechRecognizer.stopTranscribing()
            }
        }
        // Recognition can end on its own (final result, error, ~1-minute
        // limit): reflect that in the button instead of staying stuck on
        // "recording" (review 2026-11-24).
        .onChange(of: speechRecognizer.isActive) { _, active in
            if !active { isRecording = false }
        }
        // Don't leave the mic capturing after the view goes away.
        .onDisappear {
            speechRecognizer.stopTranscribing()
        }
    }
}


struct MeetingView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingView(speechRecognizer: SpeechRecognizer(), isRecording: .constant(true))
    }
}

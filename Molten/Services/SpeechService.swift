//
//  SpeechService.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 26/05/2024.
//

import Foundation
import AVFoundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.ondemandworld.molten", category: "speech")


final class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    var onSpeechFinished: (() -> Void)?
    var onSpeechStart: (() -> Void)?
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onSpeechFinished?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onSpeechStart?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didReceiveError error: Error, for utterance: AVSpeechUtterance, at characterIndex: UInt) {
        logger.error("Speech synthesis error: \(error.localizedDescription, privacy: .private)")
    }
}

@MainActor final class SpeechSynthesizer: NSObject, ObservableObject {
    static let shared = SpeechSynthesizer()
    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechSynthesizerDelegate()
    
    @Published var isSpeaking = false
    @Published var voices: [AVSpeechSynthesisVoice] = []
    
    override init() {
        super.init()
        synthesizer.delegate = delegate
        fetchVoices()
    }
    
    func getVoiceIdentifier() -> String? {
        let voiceIdentifier = UserDefaults.standard.string(forKey: "voiceIdentifier")
        if let voice = voices.first(where: {$0.identifier == voiceIdentifier}) {
            return voice.identifier
        }
        
        return voices.first?.identifier
    }
    
    var lastCancelation: (()->Void)? = {}
    
    func speak(text: String, onFinished: @escaping () -> Void = {}) async {
        guard let voiceIdentifier = getVoiceIdentifier() else {
            return
        }
        
#if os(iOS)
        let audioSession = AVAudioSession()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: .duckOthers)
            try audioSession.setActive(false)
        } catch let error {
            logger.error("Audio session error: \(error.localizedDescription, privacy: .private)")
        }
#endif
        
        lastCancelation = onFinished
        delegate.onSpeechFinished = {
            withAnimation {
                self.isSpeaking = false
            }
            onFinished()
        }
        delegate.onSpeechStart = {
            withAnimation {
                self.isSpeaking = true
            }
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier)
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }
    
    func stopSpeaking() async {
        withAnimation {
            isSpeaking = false
        }
        lastCancelation?()
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    
    func fetchVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices().sorted { (firstVoice: AVSpeechSynthesisVoice, secondVoice: AVSpeechSynthesisVoice) -> Bool in
            return firstVoice.quality.rawValue > secondVoice.quality.rawValue
        }
        
        /// prevent state refresh if there are no new elements
        let diff = self.voices.elementsEqual(voices, by: { $0.identifier == $1.identifier })
        if diff {
            return
        }
        
        DispatchQueue.main.async {
            self.voices = voices
        }
    }
}

//
//  SpeechRecogniser.swift
//  Molten
//
//  Created by Augustinas Malinauskas on 21/12/2023.
//

//#if os(iOS)
import Foundation
import Speech
import AVFoundation

@MainActor final class SpeechRecognizer: ObservableObject {
    enum RecognizerError: Error {
        case nilRecognizer
        case notAuthorizedToRecognize
        case notPermittedToRecord
        case recognizerIsUnavailable
        case noAudioInput

        var message: String {
            switch self {
            case .nilRecognizer: return "Can't initialize speech recognizer"
            case .notAuthorizedToRecognize: return "Not authorized to recognize speech"
            case .notPermittedToRecord: return "Not permitted to record audio"
            case .recognizerIsUnavailable: return "Recognizer is unavailable"
            case .noAudioInput: return "No audio input available"
            }
        }
    }
    
    @Published var transcript: String = ""
    /// True while a recognition task is running. Views bind their recording
    /// state to this so a failure or natural end resets the UI
    /// (review 2026-11-24: isRecording used to stay stuck on).
    @Published private(set) var isActive = false

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    var recognizer: SFSpeechRecognizer?
    private var onUpdate: (@Sendable (String) -> ())?
    
    /**
     Initializes a new speech recognizer. If this is the first time you've used the class, it
     requests access to the speech recognizer and the microphone.
     */
    func userInit() {
        if recognizer != nil {
            return
        }
        
        recognizer = SFSpeechRecognizer()
        guard recognizer != nil else {
            transcribe(RecognizerError.nilRecognizer)
            return
        }
        
        Task {
            do {


                guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
                    throw RecognizerError.notAuthorizedToRecognize
                }
#if os(iOS)
                guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
                    throw RecognizerError.notPermittedToRecord
                }
#endif
            } catch {
                transcribe(error)
            }
        }
    }
    
    private func setUpdateHandler(_ handler: @escaping @Sendable (_ message: String) -> ()) {
        onUpdate = handler
    }
    
    func startTranscribing(onUpdate: @escaping @Sendable (_ message: String) -> ()) {
        Task {
            await self.setUpdateHandler(onUpdate)
            await transcribe()
        }
    }
    
    func resetTranscript() {
        Task {
            await reset()
        }
    }
    
    func stopTranscribing() {
        Task {
            await reset()
        }
    }
    
    /**
     Begin transcribing audio.
     
     Creates a `SFSpeechRecognitionTask` that transcribes speech to text until you call `stopTranscribing()`.
     The resulting transcription is continuously written to the published `transcript` property.
     */
    private func transcribe() async {
        guard let recognizer, recognizer.isAvailable else {
            self.transcribe(RecognizerError.recognizerIsUnavailable)
            return
        }

        // Await authorization here, not only in userInit's fire-and-forget
        // Task: recording must not start before speech/mic permission
        // resolves (first-use race, review 2026-11-24). Both calls are
        // idempotent once the user has answered.
        guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
            self.transcribe(RecognizerError.notAuthorizedToRecognize)
            return
        }
#if os(macOS)
        // macOS mic (TCC) permission must be resolved before the engine
        // starts: with access denied or no input device, the input node's
        // format is 0 Hz / 0 channels and installTap raises an NSException
        // that Swift do/catch cannot catch (review 2026-11-24).
        guard await AVCaptureDevice.hasAudioPermission() else {
            self.transcribe(RecognizerError.notPermittedToRecord)
            return
        }
#else
        guard await AVAudioSession.sharedInstance().hasPermissionToRecord() else {
            self.transcribe(RecognizerError.notPermittedToRecord)
            return
        }
#endif

        do {
            let (audioEngine, request) = try Self.prepareEngine()
            // Privacy: keep audio on-device whenever the recognizer supports
            // it — Molten is a local-first app (review 2026-11-24).
            if recognizer.supportsOnDeviceRecognition {
                request.requiresOnDeviceRecognition = true
            }
            self.audioEngine = audioEngine
            self.request = request
            self.task = recognizer.recognitionTask(with: request, resultHandler: { [weak self] result, error in
                self?.recognitionHandler(audioEngine: audioEngine, result: result, error: error)
            })
            isActive = true
        } catch {
            self.reset()
            self.transcribe(error)
        }
    }

    /// Reset the speech recognizer.
    private func reset() {
        task?.cancel()
        audioEngine?.stop()
        audioEngine = nil
        request = nil
        task = nil
        isActive = false
#if os(iOS)
        // Release the .playAndRecord + duckOthers session so other apps'
        // audio stops being ducked after voice input ends (review 2026-11-24).
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
    
    private static func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
#if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
#endif
        let inputNode = audioEngine.inputNode

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        // installTap with a 0 Hz / 0-channel format (mic denied, no input
        // device) raises an uncatchable NSException — validate first and
        // fail as a typed error instead (review 2026-11-24).
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            throw RecognizerError.noAudioInput
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()
        
        return (audioEngine, request)
    }
    
    nonisolated private func recognitionHandler(audioEngine: AVAudioEngine, result: SFSpeechRecognitionResult?, error: Error?) {
        let receivedFinalResult = result?.isFinal ?? false
        let receivedError = error != nil
        
        if receivedFinalResult || receivedError {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            Task { @MainActor [weak self] in
                self?.isActive = false
            }
        }
        
        if let result {
            transcribe(result.bestTranscription.formattedString)
        }
    }
    
    
    nonisolated private func transcribe(_ message: String) {
        Task { @MainActor in
            transcript = message
            if !message.isEmpty {
                await onUpdate?(message)
            }
        }
    }
    nonisolated private func transcribe(_ error: Error) {
        var errorMessage = ""
        if let error = error as? RecognizerError {
            errorMessage += error.message
        } else {
            errorMessage += error.localizedDescription
        }
        Task { @MainActor [errorMessage] in
            transcript = "<< \(errorMessage) >>"
        }
    }
}


extension SFSpeechRecognizer {
    static func hasAuthorizationToRecognize() async -> Bool {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}


#if os(iOS)
extension AVAudioSession {
    func hasPermissionToRecord() async -> Bool {
        await withCheckedContinuation { continuation in
            requestRecordPermission { authorized in
                continuation.resume(returning: authorized)
            }
        }
    }
}
#elseif os(macOS)
extension AVCaptureDevice {
    /// macOS microphone (TCC) authorization, prompting on first use.
    static func hasAudioPermission() async -> Bool {
        switch authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await requestAccess(for: .audio)
        default:
            return false
        }
    }
}
#endif
//#endif

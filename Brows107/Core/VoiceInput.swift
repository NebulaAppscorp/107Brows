//
//  VoiceInput.swift
//  Brows107
//
//  Created by Aleksandra Savchuk on 06/11/26.
//

import SwiftUI
import UIKit
import Speech
import AVFoundation


/// Nonisolated audio/speech helpers so Swift 6 never injects `@MainActor` queue assertions into CoreAudio/Speech background callbacks.
enum VoiceDictationRuntime {
    // Request speech authorization
    nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {  
        // local current
        let current = SFSpeechRecognizer.authorizationStatus()
        if current != .notDetermined { return current } 
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        } 
    }

    // request microphone permission
    nonisolated static func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        // When granted
        case .granted:
            return true
        // denied case
        case .denied:
            return false
        // when undetermined
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }
}

// MARK: - VoiceDictationRuntime helpers
extension VoiceDictationRuntime {
    // activate audio session
    nonisolated static func activateAudioSession() async -> Bool {
        // wait for it before moving on
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(
                    .playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                return true
            } catch {
                return false
            }
        }.value
    }

    nonisolated static func deactivateAudioSession() {
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // Sets up tap
    nonisolated static func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }  
    }


    // Starts recognition task
    nonisolated static func startRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @Sendable (_ transcript: String?, _ isFinal: Bool, _ speechFaulted: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let transcript = result?.bestTranscription.formattedString
            // local is final
            let isFinal = result?.isFinal ?? false
            let speechFaulted = error != nil
            onEvent(transcript, isFinal, speechFaulted)
        }
    }
}

/// Turns speech into text for a search field. One session at a time, so a second mic stops the first. 
@MainActor
final class VoiceDictation: ObservableObject {
    // current shared
    static let shared = VoiceDictation()
    @Published private(set) var listening = false
    @Published private(set) var activeID: UUID?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var dictationSeed = ""
    private var update: ((String) -> Void)?
    private var sessionToken = UUID()
    // begin task
    private var beginTask: Task<Void, Never>?
    private var hasTap = false

    // flips it
    func toggle(
        id: UUID,
        text draftText: String,
        onError: ((String) -> Void)? = nil,
        update: @escaping (String) -> Void
    ) { 
        if listening, activeID == id {
            stop()
            return
        }
        beginTask?.cancel()
        beginTask = Task {
            // wait for it before moving on
            await begin(id: id, text: draftText, onError: onError, update: update)
        }
    }

    // starts it
    private func begin(
        id: UUID,
        text draftText: String,
        onError: ((String) -> Void)?,
        update: @escaping (String) -> Void
    ) async {
        let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { 
            onError?("Voice input isn’t available on this device right now.")
            return
        }
        guard !Task.isCancelled else { return }

        let speechStatus = await VoiceDictationRuntime.requestSpeechAuthorization()
        // skip when the input is unusable
        guard !Task.isCancelled else { return }
        guard speechStatus == .authorized else {  
            onError?("Allow Speech Recognition in Settings to use voice search.")
            return
        }

        let micOK = await VoiceDictationRuntime.requestMicrophonePermission()
        guard !Task.isCancelled else { return }
        guard micOK else {
            onError?("Allow Microphone access in Settings to use voice search.")
            return
        }

        await start(id: id, text: draftText, recognizer: recognizer, onError: onError, update: update)
        beginTask = nil
    }


    // Starts it
    private func start(
        id: UUID,
        text draftText: String,
        recognizer: SFSpeechRecognizer,
        onError: ((String) -> Void)?,
        update: @escaping (String) -> Void
    ) async {
        tearDownRecording()
        let token = UUID()
        sessionToken = token

        let activated = await VoiceDictationRuntime.activateAudioSession()
        guard !Task.isCancelled, sessionToken == token else {
            VoiceDictationRuntime.deactivateAudioSession()
            return
        }
        guard activated else {
            onError?("Microphone couldn’t start right now.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            VoiceDictationRuntime.deactivateAudioSession()
            onError?("No audio input is available right now.")
            return
        }

        self.engine = engine
        self.request = request
        self.dictationSeed = draftText
        self.update = update
        self.activeID = id
        self.listening = true

        VoiceDictationRuntime.installTap(on: input, format: format, request: request)
        hasTap = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            tearDownRecording()
            listening = false
            activeID = nil
            onError?("Microphone couldn’t start right now.")
            return
        }

        task = VoiceDictationRuntime.startRecognitionTask(recognizer: recognizer, request: request) {  
            [weak self] spoken, isFinal, speechFaulted in
            Task { @MainActor [weak self] in
                // self must exist here
                guard let self, self.sessionToken == token else { return }
                // Optional spoken, may be missing
                if let spoken {
                    let spacer = self.dictationSeed.isEmpty || self.dictationSeed.hasSuffix(" ") ? "" : " "
                    self.update?(self.dictationSeed + spacer + spoken)
                    if isFinal { self.stop() }
                } else if speechFaulted {
                    self.stop()
                }
            }
        }
    }

    /// Stops audio capture without cancelling an in-flight `begin` task (start() runs inside that task).
    private func tearDownRecording() {
        sessionToken = UUID()

        task?.cancel()
        self.task = nil
        request?.endAudio()
        request = nil

        // handle engine if it is there
        if let engine {
            if engine.isRunning { engine.stop() }
            if hasTap {
                engine.inputNode.removeTap(onBus: 0)
                self.hasTap = false
            }
            engine.reset()
        }
        engine = nil
        VoiceDictationRuntime.deactivateAudioSession()
    }

    // stops it
    func stop() {
        beginTask?.cancel()
        self.beginTask = nil
        tearDownRecording()
        update = nil
        listening = false
        activeID = nil
    }
}

/// Mic button that toggles VoiceDictation.
struct VoiceInputButton: View {
    // from the environment
    @Binding var draftText: String
    var onPrepare: (() -> Void)?
    var onError: ((String) -> Void)? = nil
    @ObservedObject private var voice = VoiceDictation.shared
    @State private var id = UUID()

    var body: some View {
        Button {
            if !(voice.listening && voice.activeID == id) {
                onPrepare?()
            }
            voice.toggle(id: id, text: draftText, onError: onError) { draftText = $0 }
        } label: {
            Image(systemName: voice.listening && voice.activeID == id ? "waveform" : "mic")
                .font(.ui(17))
                .foregroundStyle(voice.listening && voice.activeID == id ? Palette.brandInk : Color(uiColor: .secondaryLabel))
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(voice.listening && voice.activeID == id ? "Stop voice input" : "Voice input")
        .onDisappear { if voice.activeID == id { voice.stop() } }
    }
}

// MARK: - Fonts

#if os(macOS)
@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation
import DoricoVoiceCore

private final class SpeechRequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest
    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
}

@MainActor
final class SpeechController {
    enum ControllerError: LocalizedError {
        case speechPermissionDenied
        case microphonePermissionDenied
        case recognizerUnavailable
        case invalidInputFormat(sampleRate: Double, channels: UInt32)
        case audioStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .speechPermissionDenied: return "Speech Recognition permission was not granted."
            case .microphonePermissionDenied: return "Microphone permission was not granted."
            case .recognizerUnavailable: return "The macOS speech recognizer is currently unavailable."
            case .invalidInputFormat(let rate, let channels): return "The selected microphone returned an invalid format (\(rate) Hz, \(channels) channels)."
            case .audioStartFailed(let message): return "The microphone could not start: \(message)"
            }
        }
    }

    var onPartialTranscript: (@MainActor (String) -> Void)?
    var onFinalTranscript: (@MainActor (String) -> Void)?
    var onFailure: (@MainActor (String) -> Void)?
    var onListeningChanged: (@MainActor (Bool) -> Void)?
    var onAudioFormatChanged: (@MainActor (String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var inputTapInstalled = false
    private var silenceTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var latestPartial = ""

    var isListening: Bool { audioEngine?.isRunning == true && inputTapInstalled }

    func currentSpeechPermission() -> PermissionDisplayState {
        PermissionDisplayState(speech: SFSpeechRecognizer.authorizationStatus())
    }

    func currentMicrophonePermission() -> PermissionDisplayState {
        PermissionDisplayState(microphone: AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestRequiredPermissions() async throws {
        let speech = await requestSpeechPermissionIfNeeded()
        guard speech == .authorized else { throw ControllerError.speechPermissionDenied }
        let microphone = await requestMicrophonePermissionIfNeeded()
        guard microphone else { throw ControllerError.microphonePermissionDenied }
    }

    func start(localeIdentifier: String, contextualStrings: [String]) async throws {
        stop()
        try await requestRequiredPermissions()

        let identifier = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: identifier), recognizer.isAvailable else {
            throw ControllerError.recognizerUnavailable
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = VoiceSafetyPolicy.prioritizedContextualStrings(
            primary: contextualStrings,
            secondary: DoricoVoiceLanguage.speechHints
        )
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let channelCount = format.channelCount
        guard VoiceSafetyPolicy.isValidAudioFormat(sampleRate: format.sampleRate, channelCount: channelCount) else {
            throw ControllerError.invalidInputFormat(sampleRate: format.sampleRate, channels: channelCount)
        }

        let newSessionID = UUID()
        sessionID = newSessionID
        latestPartial = ""
        let requestBox = SpeechRequestBox(request)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            requestBox.request.append(buffer)
        }
        inputTapInstalled = true

        recognitionRequest = request
        audioEngine = engine
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorText = error?.localizedDescription
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == newSessionID else { return }
                if let transcript, !transcript.isEmpty {
                    self.receive(transcript: transcript, isFinal: isFinal, sessionID: newSessionID)
                }
                if let errorText, !isFinal {
                    self.finishWithFailure(errorText, sessionID: newSessionID)
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            throw ControllerError.audioStartFailed(error.localizedDescription)
        }
        onAudioFormatChanged?("\(Int(format.sampleRate)) Hz · \(format.channelCount) channel\(format.channelCount == 1 ? "" : "s")")
        onListeningChanged?(true)
    }

    func stop() {
        silenceTask?.cancel()
        silenceTask = nil
        sessionID = UUID()
        latestPartial = ""

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let engine = audioEngine {
            if inputTapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                inputTapInstalled = false
            }
            if engine.isRunning { engine.stop() }
            engine.reset()
        }
        audioEngine = nil
        onListeningChanged?(false)
    }

    private func receive(transcript: String, isFinal: Bool, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        latestPartial = transcript
        onPartialTranscript?(transcript)
        silenceTask?.cancel()

        if isFinal {
            finalize(transcript, sessionID: sessionID)
            return
        }

        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_250))
            guard let self, !Task.isCancelled, self.sessionID == sessionID, !self.latestPartial.isEmpty else { return }
            self.finalize(self.latestPartial, sessionID: sessionID)
        }
    }

    private func finalize(_ transcript: String, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        let finalText = transcript
        stop()
        onFinalTranscript?(finalText)
    }

    private func finishWithFailure(_ message: String, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        stop()
        onFailure?(message)
    }

    private func requestSpeechPermissionIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophonePermissionIfNeeded() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default: return false
        }
    }
}
#endif

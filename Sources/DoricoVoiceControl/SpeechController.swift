#if os(macOS)
@preconcurrency import AVFoundation
@preconcurrency import Speech
import Foundation
import DoricoVoiceCore

/// Serializes audio-buffer delivery with shutdown. The audio tap runs off the
/// main thread, so teardown must wait for any in-flight append before calling
/// `endAudio()` on the recognition request.
private final class SpeechAudioRequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    init(request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }

    /// Prevents every future append and waits for an in-flight append to finish.
    func detachRequest() -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let detached = request
        request = nil
        return detached
    }
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
    var onLifecycleEvent: (@MainActor (String) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var requestGate: SpeechAudioRequestGate?
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
        onLifecycleEvent?("Checking Speech Recognition permission")
        let speech = await requestSpeechPermissionIfNeeded()
        guard speech == .authorized else { throw ControllerError.speechPermissionDenied }

        onLifecycleEvent?("Checking Microphone permission")
        let microphone = await requestMicrophonePermissionIfNeeded()
        guard microphone else { throw ControllerError.microphonePermissionDenied }
        onLifecycleEvent?("Required permissions are granted")
    }

    func start(localeIdentifier: String, contextualStrings: [String]) async throws {
        stop(reason: "Preparing a new listening session")
        try await requestRequiredPermissions()

        let identifier = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: identifier), recognizer.isAvailable else {
            throw ControllerError.recognizerUnavailable
        }
        onLifecycleEvent?("Speech recognizer is available for \(localeIdentifier)")

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = VoiceSafetyPolicy.prioritizedContextualStrings(
            primary: contextualStrings,
            secondary: DoricoVoiceLanguage.speechHints
        )
        // Do not force the on-device recognizer. macOS may choose it when suitable,
        // but requiring it has produced unstable startup behavior on some machines.
        request.requiresOnDeviceRecognition = false

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let channelCount = format.channelCount
        guard VoiceSafetyPolicy.isValidAudioFormat(sampleRate: format.sampleRate, channelCount: channelCount) else {
            throw ControllerError.invalidInputFormat(sampleRate: format.sampleRate, channels: channelCount)
        }
        onLifecycleEvent?("Validated microphone format: \(Int(format.sampleRate)) Hz, \(channelCount) channel\(channelCount == 1 ? "" : "s")")

        let newSessionID = UUID()
        sessionID = newSessionID
        latestPartial = ""

        let gate = SpeechAudioRequestGate(request: request)
        requestGate = gate
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            gate.append(buffer)
        }
        inputTapInstalled = true
        onLifecycleEvent?("Microphone tap installed")

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
                    self.onLifecycleEvent?("Speech recognizer reported: \(errorText)")
                    self.finishWithFailure(errorText, sessionID: newSessionID)
                }
            }
        }
        onLifecycleEvent?("Recognition task created")

        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop(reason: "Audio engine failed to start")
            throw ControllerError.audioStartFailed(error.localizedDescription)
        }

        onAudioFormatChanged?("\(Int(format.sampleRate)) Hz · \(format.channelCount) channel\(format.channelCount == 1 ? "" : "s")")
        onListeningChanged?(true)
        onLifecycleEvent?("Audio engine started")
    }

    func stop(reason: String = "Stopped by user") {
        silenceTask?.cancel()
        silenceTask = nil

        // Invalidate recognition callbacks before touching any shared audio object.
        sessionID = UUID()
        latestPartial = ""
        onLifecycleEvent?("Stopping session: \(reason)")

        let engine = audioEngine
        let task = recognitionTask
        let gate = requestGate

        // First prevent the tap from scheduling new buffers, then stop the engine.
        if let engine {
            if inputTapInstalled {
                engine.inputNode.removeTap(onBus: 0)
                inputTapInstalled = false
                onLifecycleEvent?("Microphone tap removed")
            }
            if engine.isRunning {
                engine.stop()
                onLifecycleEvent?("Audio engine stopped")
            }
        }

        // Wait for any buffer already inside append(), detach the request, and only
        // then mark its audio stream as finished. This closes the crash race.
        let detachedRequest = gate?.detachRequest() ?? recognitionRequest
        requestGate = nil
        recognitionRequest = nil
        detachedRequest?.endAudio()

        recognitionTask = nil
        task?.cancel()

        engine?.reset()
        audioEngine = nil
        onListeningChanged?(false)
        onLifecycleEvent?("Session stopped cleanly")
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
            try? await Task.sleep(for: .milliseconds(1_500))
            guard let self, !Task.isCancelled, self.sessionID == sessionID, !self.latestPartial.isEmpty else { return }
            self.finalize(self.latestPartial, sessionID: sessionID)
        }
    }

    private func finalize(_ transcript: String, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        let finalText = transcript
        stop(reason: "Transcript finalized")
        onFinalTranscript?(finalText)
    }

    private func finishWithFailure(_ message: String, sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        stop(reason: "Recognition failure")
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

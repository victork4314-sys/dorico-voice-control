#if os(macOS)
import AppKit
import AVFoundation
import Combine
import Speech
import Foundation
import DoricoVoiceCore

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: VoiceEnginePhase = .idle
    @Published var speechPermission: PermissionDisplayState = .notDetermined
    @Published var microphonePermission: PermissionDisplayState = .notDetermined
    @Published var accessibilityGranted = false
    @Published var isListening = false
    @Published var partialTranscript = ""
    @Published var finalTranscript = ""
    @Published var currentBatch = DoricoVoiceBatch(commands: [])
    @Published var planError: String?
    @Published var statusMessage = "Ready to listen."
    @Published var audioFormat = "Not started"
    @Published var diagnostics: [DiagnosticEntry] = []
    @Published var preferences: AppPreferences
    @Published var calibrationExpected: String?

    private let store = PersistentStore()
    private let speechController = SpeechController()
    private let executor = DoricoCommandExecutor()
    private var safetyPolicy = VoiceSafetyPolicy()

    init() {
        preferences = store.loadPreferences()
        wireSpeechController()
        refreshPermissions()
        log("Lifecycle", "Dorico Voice Control launched")
    }

    var canRunPreview: Bool {
        guard !currentBatch.commands.isEmpty else { return false }
        return (try? safetyPolicy.executionPlan(for: currentBatch, automatic: false)) != nil
    }

    var autoExecute: Bool {
        get { preferences.autoExecuteHighConfidencePlans }
        set {
            preferences.autoExecuteHighConfidencePlans = newValue
            persistPreferences()
            objectWillChange.send()
        }
    }

    func refreshPermissions() {
        speechPermission = speechController.currentSpeechPermission()
        microphonePermission = speechController.currentMicrophonePermission()
        accessibilityGranted = executor.isAccessibilityGranted
    }

    func toggleListening() {
        if isListening {
            speechController.stop()
            phase = .stopped
            statusMessage = "Listening stopped."
            return
        }
        Task { await startListening() }
    }

    func startListening() async {
        phase = .requestingPermissions
        statusMessage = "Checking Speech Recognition and Microphone permissions…"
        planError = nil
        do {
            let customHints = Array(preferences.aliases.aliases.keys) + Array(preferences.calibration.phraseSamples.keys)
            phase = .starting
            try await speechController.start(localeIdentifier: preferences.localeIdentifier, contextualStrings: customHints)
            refreshPermissions()
            phase = .listening
            statusMessage = calibrationExpected == nil ? "Listening for a Dorico command…" : "Listening for the setup phrase…"
            log("Speech", "Listening started using \(preferences.localeIdentifier)")
        } catch {
            refreshPermissions()
            phase = .failed
            statusMessage = error.localizedDescription
            planError = error.localizedDescription
            log("Speech error", error.localizedDescription)
        }
    }

    func runPreview() {
        Task { await executeCurrentBatch(automatic: false) }
    }

    func clearPreview() {
        currentBatch = DoricoVoiceBatch(commands: [])
        partialTranscript = ""
        finalTranscript = ""
        planError = nil
        statusMessage = "Preview cleared."
    }

    func requestAccessibilityPermission() {
        executor.requestAccessibilityPermission()
        log("Permission", "Requested Accessibility permission")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            refreshPermissions()
        }
    }

    func openSpeechSettings() {
        openPrivacyPane("Privacy_SpeechRecognition")
    }

    func openMicrophoneSettings() {
        openPrivacyPane("Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openDiagnosticsFolder() {
        NSWorkspace.shared.open(store.directory)
    }

    func beginCalibration(expected: String) {
        calibrationExpected = expected
        partialTranscript = ""
        finalTranscript = ""
        Task { await startListening() }
    }

    func cancelCalibrationListening() {
        calibrationExpected = nil
        speechController.stop()
    }

    func resetCalibration() {
        preferences.calibration.reset()
        persistPreferences()
        statusMessage = "Voice setup was reset."
        log("Calibration", "Calibration reset")
    }

    func teachAlias(heard: String, canonical: String) -> String? {
        guard DoricoVoiceLanguage.canTeach(canonicalPhrase: canonical) else {
            return "The target phrase is not a complete recognized Dorico command."
        }
        preferences.aliases.teach(samples: [heard], canonicalPhrase: canonical)
        persistPreferences()
        log("Alias", "Added a pronunciation alias for \(DoricoVoiceLanguage.normalize(canonical))")
        return nil
    }

    func removeAllAliases() {
        preferences.aliases.removeAll()
        persistPreferences()
        log("Alias", "Removed all custom aliases")
    }

    private func wireSpeechController() {
        speechController.onPartialTranscript = { [weak self] value in
            self?.partialTranscript = value
        }
        speechController.onFinalTranscript = { [weak self] value in
            self?.handleFinalTranscript(value)
        }
        speechController.onFailure = { [weak self] value in
            guard let self else { return }
            self.phase = .failed
            self.statusMessage = value
            self.planError = value
            self.log("Speech error", value)
        }
        speechController.onListeningChanged = { [weak self] value in
            self?.isListening = value
        }
        speechController.onAudioFormatChanged = { [weak self] value in
            self?.audioFormat = value
        }
    }

    private func handleFinalTranscript(_ transcript: String) {
        phase = .finalizing
        finalTranscript = transcript
        partialTranscript = transcript
        log("Transcript", transcript)

        if let expected = calibrationExpected {
            preferences.calibration.learn(expected: expected, heard: transcript)
            calibrationExpected = nil
            persistPreferences()
            phase = .idle
            statusMessage = "Setup phrase saved."
            log("Calibration", "Saved setup phrase \(preferences.calibration.completedPromptCount) of \(DoricoVoiceLanguage.calibrationPrompts.count)")
            return
        }

        let batch = DoricoVoiceLanguage.parseBatch(
            transcript,
            aliases: preferences.aliases,
            calibration: preferences.calibration
        )
        currentBatch = batch
        do {
            _ = try safetyPolicy.executionPlan(for: batch, automatic: preferences.autoExecuteHighConfidencePlans)
            planError = nil
            statusMessage = batch.commands.isEmpty ? "No Dorico command was recognized." : "Review the command plan below."
            phase = .idle
            if preferences.autoExecuteHighConfidencePlans {
                Task { await executeCurrentBatch(automatic: true) }
            }
        } catch {
            planError = error.localizedDescription
            statusMessage = error.localizedDescription
            phase = .failed
            log("Safety block", error.localizedDescription)
        }
    }

    private func executeCurrentBatch(automatic: Bool) async {
        do {
            let plan = try safetyPolicy.executionPlan(for: currentBatch, automatic: automatic)
            phase = .executing
            statusMessage = "Sending \(plan.commands.count) command\(plan.commands.count == 1 ? "" : "s") to Dorico…"
            try await executor.execute(plan)
            phase = .idle
            statusMessage = "Sent: \(plan.commands.map { $0.label }.joined(separator: " → "))"
            log("Execution", statusMessage)
        } catch {
            phase = .failed
            planError = error.localizedDescription
            statusMessage = error.localizedDescription
            log("Execution error", error.localizedDescription)
        }
        refreshPermissions()
    }

    private func persistPreferences() {
        do {
            try store.savePreferences(preferences)
        } catch {
            log("Storage error", error.localizedDescription)
        }
    }

    private func log(_ category: String, _ message: String) {
        let entry = DiagnosticEntry(category: category, message: message)
        diagnostics.insert(entry, at: 0)
        if diagnostics.count > 100 { diagnostics.removeLast(diagnostics.count - 100) }
        store.appendDiagnostic(entry)
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif

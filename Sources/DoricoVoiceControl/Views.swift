#if os(macOS)
import SwiftUI
import DoricoVoiceCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showingCalibration = false
    @State private var showingAliases = false
    @State private var showingDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                permissionCard
                listeningCard
                previewCard
                footerActions
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .frame(minWidth: 720, minHeight: 680)
        .sheet(isPresented: $showingCalibration) { CalibrationView(model: model) }
        .sheet(isPresented: $showingAliases) { AliasView(model: model) }
        .sheet(isPresented: $showingDiagnostics) { DiagnosticsView(model: model) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: model.isListening ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dorico Voice Control").font(.largeTitle.bold())
                Text("A separate voice-only app for writing and controlling Dorico").foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(model.phase.rawValue).font(.headline)
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundColor(model.phase == .failed ? .red : .secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 280, alignment: .trailing)
            }
        }
    }

    private var permissionCard: some View {
        GroupBox("Permissions and connection") {
            VStack(spacing: 10) {
                permissionRow("Speech Recognition", state: model.speechPermission.rawValue) { model.openSpeechSettings() }
                Divider()
                permissionRow("Microphone", state: model.microphonePermission.rawValue) { model.openMicrophoneSettings() }
                Divider()
                permissionRow("Accessibility", state: model.accessibilityGranted ? "Granted" : "Not granted") {
                    model.requestAccessibilityPermission()
                }
                HStack {
                    Text("Microphone format")
                    Spacer()
                    Text(model.audioFormat).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            .padding(.vertical, 4)
        }
    }

    private func permissionRow(_ title: String, state: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(state).foregroundColor(state == "Granted" ? .green : .secondary)
            Button(state == "Granted" ? "Open settings" : "Set up", action: action)
        }
    }

    private var listeningCard: some View {
        GroupBox("Listen") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        model.toggleListening()
                    } label: {
                        Label(model.isListening ? "Stop listening" : "Start listening", systemImage: model.isListening ? "stop.fill" : "mic.fill")
                            .frame(minWidth: 150)
                    }
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [.command, .shift])

                    Toggle("Automatically run only complete high-confidence plans", isOn: Binding(
                        get: { model.autoExecute },
                        set: { model.autoExecute = $0 }
                    ))
                    .toggleStyle(.switch)
                }

                Text("Automatic execution is off by default. Unknown words, ambiguous matches, low-confidence results, oversized plans, and unsafe repeats are blocked before Dorico receives anything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Transcript").font(.headline)
                    Text(model.partialTranscript.isEmpty ? "Your speech will appear here." : model.partialTranscript)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var previewCard: some View {
        GroupBox("Command preview") {
            VStack(alignment: .leading, spacing: 12) {
                if model.currentBatch.commands.isEmpty {
                    Text("Nothing is queued.").foregroundStyle(.secondary)
                } else {
                    ForEach(Array(model.currentBatch.commands.enumerated()), id: \.element.id) { index, command in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(index + 1)").monospacedDigit().foregroundStyle(.secondary)
                            Text(command.label)
                            Spacer()
                            Text("\(Int(command.confidence * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(command.confidence >= 0.82 ? .secondary : .orange)
                        }
                        if index < model.currentBatch.commands.count - 1 { Divider() }
                    }
                }

                if !model.currentBatch.unrecognizedSegments.isEmpty {
                    Label("Unrecognized: \(model.currentBatch.unrecognizedSegments.joined(separator: ", "))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if let error = model.planError {
                    Label(error, systemImage: "hand.raised.fill").foregroundStyle(.red)
                }

                HStack {
                    Button("Run in Dorico") { model.runPreview() }
                        .disabled(!model.canRunPreview || model.phase == .executing)
                        .keyboardShortcut(.return, modifiers: [.command])
                    Button("Clear") { model.clearPreview() }
                        .disabled(model.currentBatch.isEmpty && model.partialTranscript.isEmpty)
                    Spacer()
                    Text("Commands are sent only to a running Dorico application.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var footerActions: some View {
        HStack {
            Button("Set Up My Voice") { showingCalibration = true }
            Button("Pronunciation aliases") { showingAliases = true }
            Button("Diagnostics") { showingDiagnostics = true }
            Spacer()
            Text("Voice setup: \(model.preferences.calibration.completedPromptCount)/\(DoricoVoiceLanguage.calibrationPrompts.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CalibrationView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var index: Int {
        min(model.preferences.calibration.completedPromptCount, DoricoVoiceLanguage.calibrationPrompts.count - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set Up My Voice").font(.title.bold())
                    Text("Five short phrases teach reusable recognition corrections for your voice and microphone.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { model.cancelCalibrationListening(); dismiss() }
            }

            ProgressView(value: Double(model.preferences.calibration.completedPromptCount), total: Double(DoricoVoiceLanguage.calibrationPrompts.count))

            if model.preferences.calibration.isComplete {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
                    Text("Voice setup complete").font(.title2.bold())
                    Text("\(model.preferences.calibration.learnedCorrectionCount) reusable correction\(model.preferences.calibration.learnedCorrectionCount == 1 ? "" : "s") saved.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                HStack {
                    Button("Reset setup", role: .destructive) { model.resetCalibration() }
                    Spacer()
                    Button("Close") { dismiss() }
                }
            } else {
                Text("Phrase \(index + 1) of \(DoricoVoiceLanguage.calibrationPrompts.count)").font(.headline)
                Text(DoricoVoiceLanguage.calibrationPrompts[index])
                    .font(.title3)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

                if !model.partialTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("macOS heard").font(.caption.bold())
                        Text(model.partialTranscript).textSelection(.enabled)
                    }
                }

                Button {
                    if model.isListening { model.cancelCalibrationListening() }
                    else { model.beginCalibration(expected: DoricoVoiceLanguage.calibrationPrompts[index]) }
                } label: {
                    Label(model.isListening ? "Stop" : "Read this phrase", systemImage: model.isListening ? "stop.fill" : "mic.fill")
                        .frame(minWidth: 140)
                }
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 640, height: 430)
    }
}

private struct AliasItem: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

struct AliasView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var heard = ""
    @State private var canonical = ""
    @State private var errorMessage: String?

    private var items: [AliasItem] {
        model.preferences.aliases.aliases
            .map { AliasItem(key: $0.key, value: $0.value) }
            .sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Pronunciation aliases").font(.title.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Map what macOS repeatedly writes to the Dorico phrase you intended. The target must already be a complete recognized command.")
                .foregroundStyle(.secondary)

            Form {
                TextField("What macOS heard", text: $heard)
                TextField("What you meant, for example quarter note", text: $canonical)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }

            HStack {
                Button("Add alias") {
                    errorMessage = model.teachAlias(heard: heard, canonical: canonical)
                    if errorMessage == nil { heard = ""; canonical = "" }
                }
                .disabled(heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || canonical.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Remove all", role: .destructive) { model.removeAllAliases() }
                    .disabled(model.preferences.aliases.aliases.isEmpty)
                Spacer()
                Text("\(model.preferences.aliases.aliases.count) saved").foregroundStyle(.secondary)
            }

            List(items) { item in
                HStack {
                    Text(item.key)
                    Spacer()
                    Image(systemName: "arrow.right")
                    Text(item.value).bold()
                }
            }
        }
        .padding(24)
        .frame(width: 680, height: 520)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Diagnostics").font(.title.bold())
                Spacer()
                Button("Open logs folder") { model.openDiagnosticsFolder() }
                Button("Done") { dismiss() }
            }
            Text("These entries record permission, microphone, recognition, safety, and execution state without storing audio.")
                .foregroundStyle(.secondary)
            List(model.diagnostics) { entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.category).bold()
                        Spacer()
                        Text(entry.timestamp, style: .time).foregroundStyle(.secondary)
                    }
                    Text(entry.message).textSelection(.enabled)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(20)
        .frame(width: 760, height: 520)
    }
}
#endif

#if os(macOS)
import SwiftUI

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
                ContentUnavailableView(
                    "Voice setup complete",
                    systemImage: "checkmark.circle.fill",
                    description: Text("\(model.preferences.calibration.learnedCorrectionCount) reusable correction\(model.preferences.calibration.learnedCorrectionCount == 1 ? "" : "s") saved.")
                )
                HStack {
                    Button("Reset setup", role: .destructive) { model.resetCalibration() }
                    Spacer()
                    Button("Close") { dismiss() }
                }
            } else {
                Text("Phrase \(index + 1) of \(DoricoVoiceLanguage.calibrationPrompts.count)")
                    .font(.headline)
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
                    if model.isListening {
                        model.cancelCalibrationListening()
                    } else {
                        model.beginCalibration(expected: DoricoVoiceLanguage.calibrationPrompts[index])
                    }
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
#endif

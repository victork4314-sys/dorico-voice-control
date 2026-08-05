#if os(macOS)
import SwiftUI
import DoricoVoiceCore

struct CommandPreviewView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GroupBox("Command preview") {
            VStack(alignment: .leading, spacing: 12) {
                CommandRows(commands: model.currentBatch.commands)
                PreviewMessages(
                    unknownSegments: model.currentBatch.unrecognizedSegments,
                    planError: model.planError
                )
                PreviewButtons(model: model)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct CommandRows: View {
    let commands: [DoricoVoiceCommand]

    var body: some View {
        if commands.isEmpty {
            Text("Nothing is queued.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                    CommandRow(index: index, command: command)
                    if index < commands.count - 1 { Divider() }
                }
            }
        }
    }
}

private struct CommandRow: View {
    let index: Int
    let command: DoricoVoiceCommand

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(index + 1)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(command.label)
            Spacer()
            Text("\(Int(command.confidence * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(command.confidence >= 0.82 ? .secondary : .orange)
        }
    }
}

private struct PreviewMessages: View {
    let unknownSegments: [String]
    let planError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !unknownSegments.isEmpty {
                Label(
                    "Unrecognized: \(unknownSegments.joined(separator: ", "))",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
            if let planError {
                Label(planError, systemImage: "hand.raised.fill")
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct PreviewButtons: View {
    @ObservedObject var model: AppModel

    var body: some View {
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
}
#endif

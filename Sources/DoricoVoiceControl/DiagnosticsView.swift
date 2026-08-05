#if os(macOS)
import SwiftUI

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

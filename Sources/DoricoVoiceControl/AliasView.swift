#if os(macOS)
import SwiftUI

struct AliasView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var heard = ""
    @State private var canonical = ""
    @State private var errorMessage: String?

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
                Text("\(model.preferences.aliases.aliases.count) saved")
                    .foregroundStyle(.secondary)
            }

            List(model.preferences.aliases.aliases.sorted(by: { $0.key < $1.key }), id: \.key) { item in
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
#endif

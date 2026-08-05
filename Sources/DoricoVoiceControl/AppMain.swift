#if os(macOS)
import SwiftUI

@main
struct DoricoVoiceControlApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .help) {
                Button("Open Diagnostics Folder") { model.openDiagnosticsFolder() }
            }
        }
    }
}
#else
import Foundation

@main
struct UnsupportedPlatformMain {
    static func main() {
        print("Dorico Voice Control is a macOS application.")
    }
}
#endif

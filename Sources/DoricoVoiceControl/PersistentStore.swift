#if os(macOS)
import Foundation

struct PersistentStore: Sendable {
    private let directoryURL: URL
    private let preferencesURL: URL
    private let diagnosticsURL: URL

    init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        directoryURL = base.appendingPathComponent("Dorico Voice Control", isDirectory: true)
        preferencesURL = directoryURL.appendingPathComponent("preferences.json")
        diagnosticsURL = directoryURL.appendingPathComponent("diagnostics.jsonl")
    }

    func loadPreferences() -> AppPreferences {
        do {
            let data = try Data(contentsOf: preferencesURL)
            return try JSONDecoder().decode(AppPreferences.self, from: data)
        } catch {
            return AppPreferences()
        }
    }

    func savePreferences(_ preferences: AppPreferences) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: preferencesURL, options: [.atomic])
    }

    func appendDiagnostic(_ entry: DiagnosticEntry) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var data = try encoder.encode(entry)
            data.append(0x0A)
            if FileManager.default.fileExists(atPath: diagnosticsURL.path) {
                let handle = try FileHandle(forWritingTo: diagnosticsURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: diagnosticsURL, options: [.atomic])
            }
        } catch {
            // Diagnostics must never become a new crash source.
        }
    }

    var directory: URL { directoryURL }
}
#endif

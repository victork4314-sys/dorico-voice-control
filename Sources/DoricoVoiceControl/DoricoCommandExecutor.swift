#if os(macOS)
import AppKit
import ApplicationServices
import Foundation
import DoricoVoiceCore

@MainActor
final class DoricoCommandExecutor {
    enum ExecutorError: LocalizedError {
        case accessibilityPermissionMissing
        case doricoNotRunning
        case unsupportedKey(String)
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionMissing: return "Accessibility permission is required before commands can be sent to Dorico."
            case .doricoNotRunning: return "Dorico is not currently running."
            case .unsupportedKey(let key): return "The key “\(key)” is not supported by the command sender."
            case .eventCreationFailed: return "macOS could not create a keyboard event."
            }
        }
    }

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func execute(_ plan: VoiceExecutionPlan) async throws {
        guard isAccessibilityGranted else { throw ExecutorError.accessibilityPermissionMissing }
        guard let dorico = runningDoricoApplication() else { throw ExecutorError.doricoNotRunning }

        _ = dorico.activate(options: [.activateIgnoringOtherApps])
        try await Task.sleep(for: .milliseconds(180))

        for step in plan.flattenedSteps {
            try Task.checkCancellation()
            if step.delayMilliseconds > 0 {
                try await Task.sleep(for: .milliseconds(step.delayMilliseconds))
            }
            switch step.action {
            case .keyChord(let chord): try post(chord)
            case .typeText(let text): try post(text: text)
            case .sequence: break
            }
        }
    }

    private func runningDoricoApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { application in
            let name = application.localizedName?.lowercased() ?? ""
            let identifier = application.bundleIdentifier?.lowercased() ?? ""
            return name == "dorico" || name.hasPrefix("dorico ") || identifier.contains("steinberg.dorico")
        }
    }

    private func post(_ chord: KeyChord) throws {
        guard let keyCode = Self.keyCode(for: chord.key) else { throw ExecutorError.unsupportedKey(chord.key) }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw ExecutorError.eventCreationFailed
        }
        let flags = Self.flags(for: chord.modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func post(text: String) throws {
        guard !text.isEmpty else { return }
        let chunks = text.utf16.reduce(into: [[UniChar]]()) { result, character in
            if result.isEmpty || result[result.count - 1].count == 20 { result.append([]) }
            result[result.count - 1].append(character)
        }
        for chunk in chunks {
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw ExecutorError.eventCreationFailed
            }
            try chunk.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { throw ExecutorError.eventCreationFailed }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private static func flags(for modifiers: Set<KeyModifier>) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private static func keyCode(for key: String) -> CGKeyCode? {
        let values: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
            "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
            "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
            "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
            "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50, "delete": 51, "escape": 53,
            "left": 123, "right": 124, "down": 125, "up": 126, "home": 115, "end": 119, "pageup": 116, "pagedown": 121
        ]
        return values[key.lowercased()]
    }
}
#endif

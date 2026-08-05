import Foundation

public enum KeyModifier: String, Codable, CaseIterable, Hashable, Sendable {
    case command
    case option
    case control
    case shift
    case function
}

public struct KeyChord: Codable, Hashable, Sendable {
    public var key: String
    public var modifiers: Set<KeyModifier>

    public init(_ key: String, modifiers: Set<KeyModifier> = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }
}

public indirect enum CommandAction: Codable, Hashable, Sendable {
    case keyChord(KeyChord)
    case typeText(String)
    case sequence([CommandStep])
}

public struct CommandStep: Codable, Hashable, Sendable {
    public var action: CommandAction
    public var delayMilliseconds: Int

    public init(_ action: CommandAction, delayMilliseconds: Int = 0) {
        self.action = action
        self.delayMilliseconds = delayMilliseconds
    }
}

public struct DoricoVoiceCommand: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var label: String
    public var canonicalPhrase: String
    public var action: CommandAction
    public var confidence: Double

    public init(id: UUID = UUID(), label: String, canonicalPhrase: String, action: CommandAction, confidence: Double = 1) {
        self.id = id
        self.label = label
        self.canonicalPhrase = canonicalPhrase
        self.action = action
        self.confidence = min(max(confidence, 0), 1)
    }
}

public struct DoricoVoiceBatch: Codable, Hashable, Sendable {
    public var commands: [DoricoVoiceCommand]
    public var unrecognizedSegments: [String]
    public var originalText: String

    public init(commands: [DoricoVoiceCommand], unrecognizedSegments: [String] = [], originalText: String = "") {
        self.commands = commands
        self.unrecognizedSegments = unrecognizedSegments
        self.originalText = originalText
    }

    public var label: String { commands.map(\.label).joined(separator: " → ") }
    public var isEmpty: Bool { commands.isEmpty && unrecognizedSegments.isEmpty }
}

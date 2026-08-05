import Foundation

public enum VoiceSafetyError: Error, Equatable, LocalizedError, Sendable {
    case noCommands
    case containsUnknownSegments([String])
    case tooManyCommands(Int)
    case tooManySteps(Int)
    case repeatLimitExceeded(Int)
    case typedTextTooLong(Int)
    case invalidDelay(Int)
    case totalDelayTooLong(Int)
    case lowConfidence(Double)

    public var errorDescription: String? {
        switch self {
        case .noCommands: return "No recognized Dorico commands were found."
        case .containsUnknownSegments(let values): return "Unrecognized speech: \(values.joined(separator: ", "))."
        case .tooManyCommands(let value): return "The phrase produced \(value) commands, which is above the safety limit."
        case .tooManySteps(let value): return "The command plan contains \(value) execution steps, which is above the safety limit."
        case .repeatLimitExceeded(let value): return "A repeated action requested \(value) events, which is above the safety limit."
        case .typedTextTooLong(let value): return "The command would type \(value) characters, which is above the safety limit."
        case .invalidDelay(let value): return "The command contains an invalid \(value) ms delay."
        case .totalDelayTooLong(let value): return "The command plan contains \(value) ms of delays, which is above the safety limit."
        case .lowConfidence(let value): return "Recognition confidence \(String(format: "%.0f", value * 100))% is below the execution threshold."
        }
    }
}

public struct VoiceExecutionPlan: Hashable, Sendable {
    public var commands: [DoricoVoiceCommand]
    public var flattenedSteps: [CommandStep]

    public init(commands: [DoricoVoiceCommand], flattenedSteps: [CommandStep]) {
        self.commands = commands
        self.flattenedSteps = flattenedSteps
    }
}

public struct VoiceSafetyPolicy: Hashable, Sendable {
    public static let maximumContextualStrings = 100

    public var maximumCommands = 24
    public var maximumSteps = 128
    public var maximumRepeatedEvents = 64
    public var maximumTypedCharacters = 256
    public var maximumStepDelayMilliseconds = 750
    public var maximumTotalDelayMilliseconds = 12_000
    public var minimumAutomaticConfidence = 0.82
    public var blockUnknownSegments = true

    public init() {}

    public func executionPlan(for batch: DoricoVoiceBatch, automatic: Bool) throws -> VoiceExecutionPlan {
        guard !batch.commands.isEmpty else { throw VoiceSafetyError.noCommands }
        if blockUnknownSegments, !batch.unrecognizedSegments.isEmpty {
            throw VoiceSafetyError.containsUnknownSegments(batch.unrecognizedSegments)
        }
        guard batch.commands.count <= maximumCommands else { throw VoiceSafetyError.tooManyCommands(batch.commands.count) }
        if automatic, let minimum = batch.commands.map(\.confidence).min(), minimum < minimumAutomaticConfidence {
            throw VoiceSafetyError.lowConfidence(minimum)
        }

        var flattened: [CommandStep] = []
        for command in batch.commands { try flatten(command.action, into: &flattened) }
        guard flattened.count <= maximumSteps else { throw VoiceSafetyError.tooManySteps(flattened.count) }
        let totalDelay = flattened.reduce(0) { $0 + $1.delayMilliseconds }
        guard totalDelay <= maximumTotalDelayMilliseconds else { throw VoiceSafetyError.totalDelayTooLong(totalDelay) }
        return VoiceExecutionPlan(commands: batch.commands, flattenedSteps: flattened)
    }

    private func flatten(_ action: CommandAction, into output: inout [CommandStep]) throws {
        switch action {
        case .keyChord:
            output.append(CommandStep(action))
        case .typeText(let text):
            guard text.count <= maximumTypedCharacters else { throw VoiceSafetyError.typedTextTooLong(text.count) }
            output.append(CommandStep(action))
        case .sequence(let steps):
            guard steps.count <= maximumRepeatedEvents else { throw VoiceSafetyError.repeatLimitExceeded(steps.count) }
            for step in steps {
                guard (0...maximumStepDelayMilliseconds).contains(step.delayMilliseconds) else {
                    throw VoiceSafetyError.invalidDelay(step.delayMilliseconds)
                }
                let before = output.count
                try flatten(step.action, into: &output)
                if output.count > before { output[before].delayMilliseconds += step.delayMilliseconds }
            }
        }
    }

    public static func prioritizedContextualStrings(primary: [String], secondary: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in primary + secondary {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
            if result.count == maximumContextualStrings { break }
        }
        return result
    }

    public static func isValidAudioFormat(sampleRate: Double, channelCount: UInt32) -> Bool {
        sampleRate.isFinite && sampleRate > 0 && channelCount > 0
    }
}

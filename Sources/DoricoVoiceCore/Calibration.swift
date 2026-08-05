import Foundation

public struct DoricoVoiceAliasBook: Codable, Hashable, Sendable {
    public var aliases: [String: String]

    public init(aliases: [String: String] = [:]) {
        self.aliases = Dictionary(uniqueKeysWithValues: aliases.map {
            (DoricoVoiceLanguage.normalize($0.key), DoricoVoiceLanguage.normalize($0.value))
        })
    }

    public mutating func teach(samples: [String], canonicalPhrase: String) {
        let target = DoricoVoiceLanguage.normalize(canonicalPhrase)
        guard !target.isEmpty else { return }
        for sample in samples {
            let source = DoricoVoiceLanguage.normalize(sample)
            if !source.isEmpty { aliases[source] = target }
        }
    }

    public mutating func removeAlias(_ sample: String) {
        aliases.removeValue(forKey: DoricoVoiceLanguage.normalize(sample))
    }

    public mutating func removeAll() { aliases.removeAll() }

    public func resolve(_ phrase: String) -> String? {
        let normalized = DoricoVoiceLanguage.normalize(phrase)
        if let exact = aliases[normalized] { return exact }
        let candidates = aliases.map { (DoricoVoiceLanguage.similarity(normalized, $0.key), $0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.0 == rhs.0 { return lhs.1.count < rhs.1.count }
                return lhs.0 > rhs.0
            }
        guard let best = candidates.first, best.0 >= 0.82 else { return nil }
        if let second = candidates.dropFirst().first, best.0 - second.0 < 0.05, best.2 != second.2 { return nil }
        return best.2
    }
}

public struct DoricoVoiceCalibrationProfile: Codable, Hashable, Sendable {
    public var replacements: [String: String]
    public var phraseSamples: [String: String]
    public var completedPromptCount: Int

    public init(replacements: [String: String] = [:], phraseSamples: [String: String] = [:], completedPromptCount: Int = 0) {
        self.replacements = Dictionary(uniqueKeysWithValues: replacements.map {
            (DoricoVoiceLanguage.normalize($0.key), DoricoVoiceLanguage.normalize($0.value))
        })
        self.phraseSamples = Dictionary(uniqueKeysWithValues: phraseSamples.map {
            (DoricoVoiceLanguage.normalize($0.key), DoricoVoiceLanguage.normalize($0.value))
        })
        self.completedPromptCount = max(0, completedPromptCount)
    }

    public var isComplete: Bool { completedPromptCount >= DoricoVoiceLanguage.calibrationPrompts.count }
    public var learnedCorrectionCount: Int { replacements.count + phraseSamples.count }

    public mutating func learn(expected: String, heard: String) {
        let expected = DoricoVoiceLanguage.normalize(expected)
        let heard = DoricoVoiceLanguage.normalize(heard)
        guard !expected.isEmpty, !heard.isEmpty else { return }
        phraseSamples[heard] = expected
        for (source, target) in Self.correctionBlocks(expected: expected, heard: heard) {
            if let existing = replacements[source], existing != target {
                replacements.removeValue(forKey: source)
            } else {
                replacements[source] = target
            }
        }
        completedPromptCount = min(completedPromptCount + 1, DoricoVoiceLanguage.calibrationPrompts.count)
    }

    public mutating func reset() {
        replacements.removeAll()
        phraseSamples.removeAll()
        completedPromptCount = 0
    }

    public func apply(to text: String) -> String {
        var value = DoricoVoiceLanguage.normalize(text)
        guard !value.isEmpty else { return value }
        if let exact = phraseSamples[value] { return exact }
        let ordered = replacements.sorted {
            let lhs = $0.key.split(separator: " ").count
            let rhs = $1.key.split(separator: " ").count
            return lhs == rhs ? $0.key.count > $1.key.count : lhs > rhs
        }
        for (source, target) in ordered { value = Self.replaceTokenPhrase(source, with: target, in: value) }
        return DoricoVoiceLanguage.normalize(value)
    }

    private enum TokenEdit {
        case equal
        case substitute(expected: String, heard: String)
        case deleteExpected(String)
        case insertHeard(String)
    }

    private static let unsafeSingleTokenCorrections: Set<String> = [
        "a", "an", "and", "are", "at", "be", "by", "can", "do", "for", "from", "go",
        "i", "in", "is", "it", "left", "me", "my", "of", "on", "one", "or", "please",
        "right", "set", "the", "then", "this", "to", "two", "up", "use", "with", "you"
    ]

    private static func correctionBlocks(expected: String, heard: String) -> [(String, String)] {
        let expectedTokens = expected.split(separator: " ").map(String.init)
        let heardTokens = heard.split(separator: " ").map(String.init)
        guard !expectedTokens.isEmpty, !heardTokens.isEmpty else { return [] }

        var distance = Array(repeating: Array(repeating: 0, count: heardTokens.count + 1), count: expectedTokens.count + 1)
        for index in 0...expectedTokens.count { distance[index][0] = index }
        for index in 0...heardTokens.count { distance[0][index] = index }
        for i in 1...expectedTokens.count {
            for j in 1...heardTokens.count {
                let substitution = distance[i - 1][j - 1] + (expectedTokens[i - 1] == heardTokens[j - 1] ? 0 : 1)
                distance[i][j] = min(substitution, distance[i - 1][j] + 1, distance[i][j - 1] + 1)
            }
        }

        var edits: [TokenEdit] = []
        var i = expectedTokens.count
        var j = heardTokens.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, expectedTokens[i - 1] == heardTokens[j - 1], distance[i][j] == distance[i - 1][j - 1] {
                edits.append(.equal); i -= 1; j -= 1
            } else if i > 0, j > 0, distance[i][j] == distance[i - 1][j - 1] + 1 {
                edits.append(.substitute(expected: expectedTokens[i - 1], heard: heardTokens[j - 1])); i -= 1; j -= 1
            } else if i > 0, distance[i][j] == distance[i - 1][j] + 1 {
                edits.append(.deleteExpected(expectedTokens[i - 1])); i -= 1
            } else if j > 0 {
                edits.append(.insertHeard(heardTokens[j - 1])); j -= 1
            }
        }
        edits.reverse()

        var result: [(String, String)] = []
        var expectedBlock: [String] = []
        var heardBlock: [String] = []
        func flush() {
            defer { expectedBlock.removeAll(); heardBlock.removeAll() }
            guard !expectedBlock.isEmpty, !heardBlock.isEmpty else { return }
            let source = heardBlock.joined(separator: " ")
            let target = expectedBlock.joined(separator: " ")
            guard source != target else { return }
            if heardBlock.count == 1 {
                guard source.count >= 3, !unsafeSingleTokenCorrections.contains(source) else { return }
            }
            result.append((source, target))
        }
        for edit in edits {
            switch edit {
            case .equal: flush()
            case .substitute(let expected, let heard): expectedBlock.append(expected); heardBlock.append(heard)
            case .deleteExpected(let expected): expectedBlock.append(expected)
            case .insertHeard(let heard): heardBlock.append(heard)
            }
        }
        flush()
        return result
    }

    private static func replaceTokenPhrase(_ source: String, with target: String, in text: String) -> String {
        let sourceTokens = source.split(separator: " ").map(String.init)
        let targetTokens = target.split(separator: " ").map(String.init)
        let inputTokens = text.split(separator: " ").map(String.init)
        guard !sourceTokens.isEmpty, inputTokens.count >= sourceTokens.count else { return text }
        var output: [String] = []
        var index = 0
        while index < inputTokens.count {
            let end = index + sourceTokens.count
            if end <= inputTokens.count, Array(inputTokens[index..<end]) == sourceTokens {
                output.append(contentsOf: targetTokens)
                index = end
            } else {
                output.append(inputTokens[index])
                index += 1
            }
        }
        return output.joined(separator: " ")
    }
}

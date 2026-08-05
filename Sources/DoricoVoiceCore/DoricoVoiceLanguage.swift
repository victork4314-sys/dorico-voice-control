import Foundation

public enum DoricoVoiceLanguage {
    public static let calibrationPrompts = [
        "Dorico, write a quarter note, then an eighth note, then a sixteenth note.",
        "Dorico, enter C sharp four and E flat three, then add staccato and a tie.",
        "Dorico, add twenty five bars, move left one bar, and extend the selection right.",
        "Dorico, use a treble clef, time signature three four, and key signature E flat major.",
        "Dorico, add crescendo, fortissimo, fermata, trill, tenuto, and start playback."
    ]

    private static let coreSpeechHints = [
        "Dorico", "quarter note", "eighth note", "sixteenth note", "half note", "whole note",
        "quaver", "semiquaver", "crotchet", "minim", "semibreve", "C sharp four", "E flat three",
        "add twenty five bars", "delete four bars", "go left one bar", "go right two bars", "go to bar thirty two",
        "time signature three four", "key signature E flat major", "treble clef", "bass clef",
        "dynamic fortissimo", "tempo allegro", "crescendo", "diminuendo", "staccato", "tenuto", "fermata", "trill",
        "start note input", "stop note input", "play from selection", "extend selection right",
        "Dorico command note input options", "Dorico command add flow"
    ]

    public static var speechHints: [String] {
        Array(Set(coreSpeechHints + calibrationPrompts + directCommands.values.map(\.canonicalPhrase))).sorted()
    }

    public static func parseBatch(_ rawText: String, aliases: DoricoVoiceAliasBook = .init(), calibration: DoricoVoiceCalibrationProfile = .init()) -> DoricoVoiceBatch {
        let calibrated = calibration.apply(to: rawText)
        let prepared = prepareSeparators(calibrated)
        var commands: [DoricoVoiceCommand] = []
        var unknown: [String] = []
        for raw in prepared.split(separator: "|").map(String.init) {
            let segment = normalize(raw)
            guard !segment.isEmpty else { continue }
            let resolved = aliases.resolve(segment) ?? segment
            if let parsed = parseDense(resolved, aliases: aliases) { commands.append(contentsOf: parsed) }
            else { unknown.append(segment) }
        }
        return DoricoVoiceBatch(commands: commands, unrecognizedSegments: unknown, originalText: rawText)
    }

    public static func canTeach(canonicalPhrase: String) -> Bool {
        let batch = parseBatch(canonicalPhrase)
        return !batch.commands.isEmpty && batch.unrecognizedSegments.isEmpty
    }

    public static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "♯", with: " sharp ")
            .replacingOccurrences(of: "♭", with: " flat ")
            .replacingOccurrences(of: "-(?=[0-9])", with: " minus ", options: .regularExpression)
            .replacingOccurrences(of: "–|—|-", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9+/. ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(normalize(lhs))
        let b = Array(normalize(rhs))
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1]
            for (j, right) in b.enumerated() {
                current.append(min(current[j] + 1, previous[j + 1] + 1, previous[j] + (left == right ? 0 : 1)))
            }
            previous = current
        }
        let characterScore = 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
        let leftTokens = Set(String(a).split(separator: " "))
        let rightTokens = Set(String(b).split(separator: " "))
        let union = leftTokens.union(rightTokens)
        let tokenScore = union.isEmpty ? 1 : Double(leftTokens.intersection(rightTokens).count) / Double(union.count)
        return max(characterScore * 0.94, characterScore * 0.72 + tokenScore * 0.28)
    }

    static func prepareSeparators(_ raw: String) -> String {
        var text = raw.lowercased()
        for mark in [",", ";", ":", ".", "!", "?"] { text = text.replacingOccurrences(of: mark, with: " | ") }
        for pattern in [#"\band then\b"#, #"\bthen\b"#, #"\bafter that\b"#, #"\bfollowed by\b"#] {
            text = text.replacingOccurrences(of: pattern, with: " | ", options: .regularExpression)
        }
        return text.replacingOccurrences(of: "\\s*\\|\\s*", with: "|", options: .regularExpression)
    }

    static func parseDense(_ phrase: String, aliases: DoricoVoiceAliasBook) -> [DoricoVoiceCommand]? {
        let phrase = stripFiller(normalize(phrase))
        guard !phrase.isEmpty else { return [] }
        if let alias = aliases.resolve(phrase), alias != phrase { return parseDense(alias, aliases: .init()) }
        let words = phrase.split(separator: " ").map(String.init)
        if words.count > 1 {
            for split in stride(from: words.count - 1, through: 1, by: -1) {
                let left = words[..<split].joined(separator: " ")
                let right = words[split...].joined(separator: " ")
                if let first = parseSingle(left, fuzzy: false), let rest = parseDense(right, aliases: aliases) { return [first] + rest }
            }
        }
        if let command = parseSingle(phrase, fuzzy: true) { return [command] }
        if let range = phrase.range(of: " and "),
           let left = parseDense(String(phrase[..<range.lowerBound]), aliases: aliases),
           let right = parseDense(String(phrase[range.upperBound...]), aliases: aliases) { return left + right }
        return nil
    }

    static func parseSingle(_ rawPhrase: String, fuzzy: Bool) -> DoricoVoiceCommand? {
        let phrase = stripFiller(normalize(rawPhrase))
        if let direct = directCommands[phrase] { return direct }
        if let duration = duration(phrase, fuzzy: false) { return duration }
        if let parameter = parameterCommand(phrase) { return parameter }
        if let jumpBar = jumpBarCommand(phrase) { return jumpBar }
        guard fuzzy else { return nil }
        if let duration = duration(phrase, fuzzy: true) { return duration }

        let scored = directCommands.map { (similarity(phrase, $0.key), $0.key, $0.value) }
            .sorted { lhs, rhs in lhs.0 == rhs.0 ? lhs.1.count < rhs.1.count : lhs.0 > rhs.0 }
        guard let best = scored.first else { return nil }
        let tokenCount = phrase.split(separator: " ").count
        let threshold: Double
        if phrase.count <= 3 { threshold = 0.95 }
        else if tokenCount == 1 { threshold = phrase.count >= 7 ? 0.70 : 0.84 }
        else { threshold = 0.82 }
        guard best.0 >= threshold else { return nil }
        if let second = scored.dropFirst().first,
           second.2.canonicalPhrase != best.2.canonicalPhrase,
           best.0 - second.0 < 0.045 { return nil }
        var command = best.2
        command.confidence = best.0
        return command
    }

    static func stripFiller(_ phrase: String) -> String {
        var value = " \(phrase) "
        for filler in [
            " please ", " could you ", " can you ", " would you ", " i want you to ", " i need you to ",
            " for me ", " now ", " just ", " um ", " uh ", " dorico ", " make it ", " set it to ", " put in ", " add a "
        ] { value = value.replacingOccurrences(of: filler, with: " ") }
        return normalize(value)
    }

    static func command(_ label: String, canonical: String, _ action: CommandAction, confidence: Double = 1) -> DoricoVoiceCommand {
        DoricoVoiceCommand(label: label, canonicalPhrase: canonical, action: action, confidence: confidence)
    }

    static func popover(_ shortcut: KeyChord, _ value: String) -> CommandAction {
        .sequence([
            CommandStep(.keyChord(shortcut)),
            CommandStep(.typeText(value), delayMilliseconds: 90),
            CommandStep(.keyChord(KeyChord("return")), delayMilliseconds: 55)
        ])
    }

    static func contains(_ phrase: String, any terms: [String]) -> Bool { terms.contains(where: phrase.contains) }

    static func stripLeading(_ phrase: String, _ words: Set<String>) -> String {
        var tokens = phrase.split(separator: " ").map(String.init)
        while let first = tokens.first, words.contains(first) { tokens.removeFirst() }
        return tokens.joined(separator: " ")
    }

    static func extractNumber(_ phrase: String) -> Int? {
        if let range = phrase.range(of: #"\b[0-9]+\b"#, options: .regularExpression) { return Int(phrase[range]) }
        let small = [
            "zero": 0, "one": 1, "a": 1, "an": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
            "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
            "eighteen": 18, "nineteen": 19
        ]
        let tens = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        var total = 0
        var current = 0
        var found = false
        for token in phrase.split(separator: " ").map(String.init) {
            if let number = small[token] { current += number; found = true }
            else if let number = tens[token] { current += number; found = true }
            else if token == "hundred", found { current = max(current, 1) * 100 }
            else if token == "thousand", found { total += max(current, 1) * 1_000; current = 0 }
            else if found { break }
        }
        return found ? total + current : nil
    }

    static let directCommands: [String: DoricoVoiceCommand] = {
        var map: [String: DoricoVoiceCommand] = [:]
        func add(_ phrases: [String], _ label: String, _ canonical: String, _ action: CommandAction) {
            let value = command(label, canonical: canonical, action)
            for phrase in phrases { map[normalize(phrase)] = value }
        }
        add(["undo", "undo that", "take that back"], "Undo", "undo", .keyChord(KeyChord("z", modifiers: [.command])))
        add(["redo", "do that again"], "Redo", "redo", .keyChord(KeyChord("z", modifiers: [.command, .shift])))
        add(["copy", "copy selection"], "Copy", "copy", .keyChord(KeyChord("c", modifiers: [.command])))
        add(["paste", "paste here"], "Paste", "paste", .keyChord(KeyChord("v", modifiers: [.command])))
        add(["cut", "cut selection"], "Cut", "cut", .keyChord(KeyChord("x", modifiers: [.command])))
        add(["delete", "delete selection", "remove selection"], "Delete selection", "delete selection", .keyChord(KeyChord("delete")))
        add(["select all", "select everything"], "Select all", "select all", .keyChord(KeyChord("a", modifiers: [.command])))
        add(["start note input", "begin note input", "start writing notes"], "Start note input", "start note input", .keyChord(KeyChord("n", modifiers: [.shift])))
        add(["stop note input", "end note input", "exit note input"], "Stop note input", "stop note input", .keyChord(KeyChord("escape")))
        add(["play", "start playback"], "Start playback", "start playback", .keyChord(KeyChord("space")))
        add(["stop", "stop playback", "pause playback"], "Stop playback", "stop playback", .keyChord(KeyChord("space")))
        add(["play from selection", "play from here"], "Play from selection", "play from selection", .keyChord(KeyChord("p")))
        add(["next note", "go to next note"], "Next note", "next note", .keyChord(KeyChord("right")))
        add(["previous note", "go to previous note"], "Previous note", "previous note", .keyChord(KeyChord("left")))
        add(["next staff", "staff down"], "Next staff", "next staff", .keyChord(KeyChord("down")))
        add(["previous staff", "staff up"], "Previous staff", "previous staff", .keyChord(KeyChord("up")))
        add(["extend selection right", "select right"], "Extend selection right", "extend selection right", .keyChord(KeyChord("right", modifiers: [.shift])))
        add(["extend selection left", "select left"], "Extend selection left", "extend selection left", .keyChord(KeyChord("left", modifiers: [.shift])))
        add(["extend selection up", "select up"], "Extend selection up", "extend selection up", .keyChord(KeyChord("up", modifiers: [.shift])))
        add(["extend selection down", "select down"], "Extend selection down", "extend selection down", .keyChord(KeyChord("down", modifiers: [.shift])))
        add(["tie", "add tie"], "Tie", "add tie", .keyChord(KeyChord("t")))
        add(["dot", "dotted note", "add dot"], "Toggle rhythm dot", "dotted note", .keyChord(KeyChord(".")))
        add(["rest", "toggle rest", "rest input"], "Toggle rest input", "rest", .keyChord(KeyChord(",")))
        add(["chord mode", "toggle chord mode"], "Toggle chord mode", "chord mode", .keyChord(KeyChord("q")))
        add(["grace note", "add grace note"], "Toggle grace note", "grace note", .keyChord(KeyChord("/")))
        add(["natural", "natural accidental"], "Natural accidental", "natural", .keyChord(KeyChord("0")))
        add(["sharp", "sharp accidental"], "Sharp accidental", "sharp", .keyChord(KeyChord("=")))
        add(["flat", "flat accidental"], "Flat accidental", "flat", .keyChord(KeyChord("-")))
        add(["crescendo", "add crescendo", "get louder"], "Crescendo", "crescendo", popover(KeyChord("d", modifiers: [.shift]), "<"))
        add(["diminuendo", "decrescendo", "get quieter"], "Diminuendo", "diminuendo", popover(KeyChord("d", modifiers: [.shift]), ">"))
        add(["fermata", "add fermata"], "Fermata", "fermata", popover(KeyChord("o", modifiers: [.shift]), "fermata"))
        add(["trill", "add trill"], "Trill", "trill", popover(KeyChord("o", modifiers: [.shift]), "tr"))
        add(["slur", "add slur"], "Slur", "slur", .keyChord(KeyChord("s")))
        for value in ["staccato", "tenuto", "accent", "marcato"] {
            add([value, "add \(value)", "make \(value)"], value.capitalized, value, popover(KeyChord("p", modifiers: [.shift]), value))
        }
        return map
    }()

    static func duration(_ phrase: String, fuzzy: Bool) -> DoricoVoiceCommand? {
        let cleaned = stripLeading(phrase, ["choose", "select", "set", "use", "make", "add", "enter", "input", "a", "an", "write"])
        let variants: [([String], String, String, String)] = [
            (["128th note", "one hundred twenty eighth note"], "1", "128th note", "128th note"),
            (["64th note", "sixty fourth note"], "2", "64th note", "64th note"),
            (["32nd note", "thirty second note", "demisemiquaver"], "3", "32nd note", "32nd note"),
            (["16th note", "sixteenth note", "semiquaver"], "4", "16th note", "sixteenth note"),
            (["8th note", "eighth note", "quaver"], "5", "Eighth note", "eighth note"),
            (["quarter note", "crotchet"], "6", "Quarter note", "quarter note"),
            (["half note", "minim"], "7", "Half note", "half note"),
            (["whole note", "semibreve"], "8", "Whole note", "whole note"),
            (["double whole note", "breve"], "9", "Double whole note", "double whole note")
        ]
        var scored: [(Double, DoricoVoiceCommand)] = []
        for (phrases, key, label, canonical) in variants {
            for candidate in phrases {
                if cleaned == candidate { return command(label, canonical: canonical, .keyChord(KeyChord(key))) }
                let score = similarity(cleaned, candidate)
                if fuzzy, score >= 0.84 {
                    scored.append((score, command(label, canonical: canonical, .keyChord(KeyChord(key)), confidence: score)))
                }
            }
        }
        let sorted = scored.sorted { $0.0 > $1.0 }
        guard let best = sorted.first else { return nil }
        if let second = sorted.dropFirst().first, best.0 - second.0 < 0.04, best.1.canonicalPhrase != second.1.canonicalPhrase { return nil }
        return best.1
    }

    static func parameterCommand(_ phrase: String) -> DoricoVoiceCommand? {
        if let value = barCommand(phrase) { return value }
        if let value = barNavigation(phrase) { return value }
        if let value = goToBar(phrase) { return value }
        if let value = pitch(phrase) { return value }
        if let value = timeSignature(phrase) { return value }
        if let value = keySignature(phrase) { return value }
        if let value = clef(phrase) { return value }
        if let value = dynamic(phrase) { return value }
        return genericPopover(phrase)
    }

    static func barCommand(_ phrase: String) -> DoricoVoiceCommand? {
        let value = phrase.replacingOccurrences(of: "measures", with: "bars").replacingOccurrences(of: "measure", with: "bar")
        guard value.contains("bar") else { return nil }
        let count = extractNumber(value) ?? 1
        guard (1...64).contains(count) else { return nil }
        if contains(value, any: ["add", "insert", "create", "append", "give me"]) {
            return command("Add \(count) \(count == 1 ? "bar" : "bars")", canonical: "add \(count) bars", popover(KeyChord("b", modifiers: [.shift]), String(count)))
        }
        if contains(value, any: ["delete", "remove", "take out"]) {
            return command("Delete \(count) \(count == 1 ? "bar" : "bars")", canonical: "delete \(count) bars", popover(KeyChord("b", modifiers: [.shift]), "-\(count)"))
        }
        return nil
    }

    static func barNavigation(_ phrase: String) -> DoricoVoiceCommand? {
        let value = phrase.replacingOccurrences(of: "measures", with: "bars").replacingOccurrences(of: "measure", with: "bar")
        guard value.contains("bar") else { return nil }
        let left = contains(value, any: ["left", "back", "backward", "previous"])
        let right = contains(value, any: ["right", "forward", "next"])
        guard left != right else { return nil }
        let count = max(1, min(64, extractNumber(value) ?? 1))
        let direction = left ? "left" : "right"
        let chord = KeyChord(direction, modifiers: [.command])
        let steps = (0..<count).map { CommandStep(.keyChord(chord), delayMilliseconds: $0 == 0 ? 0 : 45) }
        return command("Move \(direction) \(count) \(count == 1 ? "bar" : "bars")", canonical: "move \(direction) \(count) bars", .sequence(steps))
    }

    static func goToBar(_ phrase: String) -> DoricoVoiceCommand? {
        guard contains(phrase, any: ["go to bar", "jump to bar", "find bar", "open bar"]),
              let number = extractNumber(phrase), (1...9999).contains(number) else { return nil }
        return command("Go to bar \(number)", canonical: "go to bar \(number)", .sequence([
            CommandStep(.keyChord(KeyChord("j"))),
            CommandStep(.keyChord(KeyChord("2", modifiers: [.control])), delayMilliseconds: 75),
            CommandStep(.typeText("b\(number)"), delayMilliseconds: 75),
            CommandStep(.keyChord(KeyChord("return")), delayMilliseconds: 50)
        ]))
    }

    static func pitch(_ phrase: String) -> DoricoVoiceCommand? {
        var value = stripLeading(phrase, ["add", "enter", "input", "play", "note", "put", "write", "an"])
        if value.hasPrefix("a ") {
            let possibleArticle = String(value.dropFirst(2))
            if let first = possibleArticle.first, "bcdefg".contains(first), possibleArticle.count == 1 || possibleArticle.dropFirst().first == " " { value = possibleArticle }
        }
        let octaveWords = ["minus one": "minus 1", "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]
        for (word, digit) in octaveWords where value.hasSuffix(" " + word) { value = String(value.dropLast(word.count)) + digit; break }
        guard let regex = try? NSRegularExpression(pattern: #"^([a-g])(?:\s*(sharp|flat|natural))?(?:\s*(minus\s*1|[0-9]))?$"#),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.length == value.utf16.count,
              let letterRange = Range(match.range(at: 1), in: value) else { return nil }
        var output = String(value[letterRange]).uppercased()
        if let range = Range(match.range(at: 2), in: value) {
            let accidental = String(value[range])
            if accidental == "sharp" { output += "#" }
            if accidental == "flat" { output += "b" }
        }
        if let range = Range(match.range(at: 3), in: value) { output += String(value[range]).replacingOccurrences(of: "minus ", with: "-") }
        return command("Enter \(output)", canonical: output, .typeText(output))
    }

    static func timeSignature(_ phrase: String) -> DoricoVoiceCommand? {
        var value = phrase
        var changed = false
        for prefix in ["add time signature ", "time signature ", "set time signature ", "meter ", "add meter "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)); changed = true; break
        }
        if value == "common time" { value = "4/4"; changed = true }
        if value == "cut time" || value == "alla breve" { value = "2/2"; changed = true }
        guard changed else { return nil }
        let words = ["one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10", "twelve": "12", "sixteen": "16"]
        let tokens = value.replacingOccurrences(of: " over ", with: " ").split(separator: " ").map { words[String($0)] ?? String($0) }
        value = value.contains("/") ? value.replacingOccurrences(of: " ", with: "") : tokens.joined(separator: "/")
        guard value.range(of: #"^[1-9][0-9]*/[1-9][0-9]*$"#, options: .regularExpression) != nil else { return nil }
        return command("Time signature \(value)", canonical: "time signature \(value)", popover(KeyChord("m", modifiers: [.shift]), value))
    }

    static func keySignature(_ phrase: String) -> DoricoVoiceCommand? {
        var value = phrase
        var changed = false
        for prefix in ["add key signature ", "key signature ", "set key signature ", "key "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)); changed = true; break
        }
        let words = value.split(separator: " ").map(String.init)
        guard changed, let letter = words.first, letter.count == 1, "abcdefg".contains(letter) else { return nil }
        var entry = letter.uppercased()
        if words.contains("flat") { entry += "b" }
        if words.contains("sharp") { entry += "#" }
        if words.contains("minor") { entry += "m" }
        return command("Key signature \(value)", canonical: "key signature \(value)", popover(KeyChord("k", modifiers: [.shift]), entry))
    }

    static func clef(_ phrase: String) -> DoricoVoiceCommand? {
        let value = stripLeading(phrase, ["add", "insert", "use", "choose", "set", "a", "an"])
        let entries = ["treble clef": "treble", "g clef": "treble", "bass clef": "bass", "f clef": "bass", "alto clef": "alto", "tenor clef": "tenor", "percussion clef": "percussion"]
        guard let entry = entries[value] else { return nil }
        return command(value.capitalized, canonical: value, popover(KeyChord("c", modifiers: [.shift]), entry))
    }

    static func dynamic(_ phrase: String) -> DoricoVoiceCommand? {
        var value = phrase
        var changed = false
        for prefix in ["add dynamic ", "dynamic ", "mark dynamic ", "make dynamic "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)); changed = true; break
        }
        let entries = [
            "pianissimo": "pp", "piano": "p", "mezzo piano": "mp", "mezzo forte": "mf", "forte": "f",
            "fortissimo": "ff", "triple forte": "fff", "triple piano": "ppp", "sforzando": "sfz",
            "sfz": "sfz", "pp": "pp", "p": "p", "mp": "mp", "mf": "mf", "f": "f", "ff": "ff", "fff": "fff", "ppp": "ppp"
        ]
        if !changed, let direct = entries[value] { return command("Dynamic \(direct)", canonical: "dynamic \(value)", popover(KeyChord("d", modifiers: [.shift]), direct)) }
        guard changed, let entry = entries[value] else { return nil }
        return command("Dynamic \(entry)", canonical: "dynamic \(value)", popover(KeyChord("d", modifiers: [.shift]), entry))
    }

    static func genericPopover(_ phrase: String) -> DoricoVoiceCommand? {
        let specifications: [([String], KeyChord, String)] = [
            (["add tempo ", "tempo ", "set tempo "], KeyChord("t", modifiers: [.shift]), "Tempo"),
            (["add playing technique ", "playing technique ", "add technique ", "technique "], KeyChord("p", modifiers: [.shift]), "Playing technique"),
            (["add ornament ", "ornament "], KeyChord("o", modifiers: [.shift]), "Ornament"),
            (["add rehearsal mark ", "rehearsal mark "], KeyChord("a", modifiers: [.shift, .command]), "Rehearsal mark")
        ]
        for (prefixes, chord, label) in specifications {
            for prefix in prefixes where phrase.hasPrefix(prefix) {
                let value = String(phrase.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty, value.count <= 128 else { return nil }
                return command("\(label) \(value)", canonical: "\(label.lowercased()) \(value)", popover(chord, value))
            }
        }
        return nil
    }

    static func jumpBarCommand(_ phrase: String) -> DoricoVoiceCommand? {
        let prefixes = ["run dorico command ", "dorico command ", "run command ", "use command ", "open command ", "command "]
        guard let prefix = prefixes.first(where: phrase.hasPrefix) else { return nil }
        let value = String(phrase.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.count <= 128 else { return nil }
        return command("Dorico command: \(value)", canonical: "dorico command \(value)", .sequence([
            CommandStep(.keyChord(KeyChord("j"))),
            CommandStep(.keyChord(KeyChord("1", modifiers: [.control])), delayMilliseconds: 90),
            CommandStep(.typeText(value), delayMilliseconds: 100),
            CommandStep(.keyChord(KeyChord("return")), delayMilliseconds: 55)
        ]))
    }
}

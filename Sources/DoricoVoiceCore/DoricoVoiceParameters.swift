import Foundation

extension DoricoVoiceLanguage {
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
            if let first = possibleArticle.first, "bcdefg".contains(first),
               possibleArticle.count == 1 || possibleArticle.dropFirst().first == " " {
                value = possibleArticle
            }
        }
        let octaveWords = ["minus one": "minus 1", "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]
        for (word, digit) in octaveWords where value.hasSuffix(" " + word) {
            value = String(value.dropLast(word.count)) + digit
            break
        }
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
        if let range = Range(match.range(at: 3), in: value) {
            output += String(value[range]).replacingOccurrences(of: "minus ", with: "-")
        }
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
        let entries = [
            "treble clef": "treble", "g clef": "treble", "bass clef": "bass", "f clef": "bass",
            "alto clef": "alto", "tenor clef": "tenor", "percussion clef": "percussion"
        ]
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
        if !changed, let direct = entries[value] {
            return command("Dynamic \(direct)", canonical: "dynamic \(value)", popover(KeyChord("d", modifiers: [.shift]), direct))
        }
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

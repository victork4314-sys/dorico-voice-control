import XCTest
@testable import DoricoVoiceCore

final class DoricoVoiceLanguageTests: XCTestCase {
    func testDirectCommand() {
        let batch = DoricoVoiceLanguage.parseBatch("undo")
        XCTAssertEqual(batch.commands.map(\.label), ["Undo"])
        XCTAssertTrue(batch.unrecognizedSegments.isEmpty)
    }

    func testOrderedMultiCommandPhrase() {
        let batch = DoricoVoiceLanguage.parseBatch("quarter note, then C sharp four, then staccato and tie")
        XCTAssertEqual(batch.commands.map(\.label), ["Quarter note", "Enter C#4", "Staccato", "Tie"])
    }

    func testSpokenDurations() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("quaver").commands.first?.label, "Eighth note")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("semiquaver").commands.first?.label, "16th note")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("minim").commands.first?.label, "Half note")
    }

    func testPitchAccidentalsAndOctaves() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("enter E flat three").commands.first?.label, "Enter Eb3")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("write C sharp four").commands.first?.label, "Enter C#4")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("A minus one").commands.first?.label, "Enter A-1")
    }

    func testBarCommands() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("add twenty five bars").commands.first?.label, "Add 25 bars")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("delete four measures").commands.first?.label, "Delete 4 bars")
    }

    func testBarRepeatIsBounded() {
        XCTAssertTrue(DoricoVoiceLanguage.parseBatch("move right sixty four bars").unrecognizedSegments.isEmpty)
        XCTAssertFalse(DoricoVoiceLanguage.parseBatch("move right sixty five bars").commands.isEmpty)
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("move right sixty five bars").commands.first?.label, "Move right 64 bars")
    }

    func testGoToBar() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("go to bar thirty two").commands.first?.label, "Go to bar 32")
    }

    func testTimeSignatures() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("time signature three four").commands.first?.label, "Time signature 3/4")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("common time").commands.first?.label, "Time signature 4/4")
    }

    func testKeySignatures() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("key signature E flat major").commands.first?.label, "Key signature e flat major")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("key F sharp minor").commands.first?.label, "Key signature f sharp minor")
    }

    func testClefs() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("use a treble clef").commands.first?.label, "Treble Clef")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("bass clef").commands.first?.label, "Bass Clef")
    }

    func testDynamicsWithoutExplicitPrefix() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("fortissimo").commands.first?.label, "Dynamic ff")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("mezzo piano").commands.first?.label, "Dynamic mp")
    }

    func testGenericPopovers() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("tempo allegro").commands.first?.label, "Tempo allegro")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("ornament mordent").commands.first?.label, "Ornament mordent")
    }

    func testGenericDoricoCommand() {
        let command = DoricoVoiceLanguage.parseBatch("Dorico command note input options").commands.first
        XCTAssertEqual(command?.label, "Dorico command: note input options")
    }

    func testUnknownSpeechRemainsUnknown() {
        let batch = DoricoVoiceLanguage.parseBatch("launch a spaceship")
        XCTAssertTrue(batch.commands.isEmpty)
        XCTAssertEqual(batch.unrecognizedSegments, ["launch a spaceship"])
    }

    func testFillerWords() {
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("Could you please Dorico add a tie for me now").commands.first?.label, "Tie")
    }

    func testTypoFuzzyRecognition() {
        let command = DoricoVoiceLanguage.parseBatch("stacatto").commands.first
        XCTAssertEqual(command?.label, "Staccato")
        XCTAssertLessThan(command?.confidence ?? 1, 1)
    }

    func testDangerouslyAmbiguousFuzzyInputIsRejected() {
        let batch = DoricoVoiceLanguage.parseBatch("sto")
        XCTAssertTrue(batch.commands.isEmpty)
        XCTAssertEqual(batch.unrecognizedSegments, ["sto"])
    }

    func testAliasBookExactAndFuzzy() {
        var aliases = DoricoVoiceAliasBook()
        aliases.teach(samples: ["quarter nude", "quarter newt"], canonicalPhrase: "quarter note")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("quarter nude", aliases: aliases).commands.first?.label, "Quarter note")
        XCTAssertEqual(DoricoVoiceLanguage.parseBatch("quarter nud", aliases: aliases).commands.first?.label, "Quarter note")
    }

    func testConflictingAliasCandidatesDoNotGuess() {
        let aliases = DoricoVoiceAliasBook(aliases: ["play now": "play", "play no": "stop"])
        XCTAssertNil(aliases.resolve("play n"))
    }

    func testCanTeachOnlyKnownCommands() {
        XCTAssertTrue(DoricoVoiceLanguage.canTeach(canonicalPhrase: "quarter note"))
        XCTAssertFalse(DoricoVoiceLanguage.canTeach(canonicalPhrase: "launch a spaceship"))
    }
}

import XCTest
@testable import DoricoVoiceCore

final class VoiceSafetyPolicyTests: XCTestCase {
    func testContextualStringsAreCappedAtOneHundred() {
        let values = VoiceSafetyPolicy.prioritizedContextualStrings(
            primary: (0..<80).map { "Primary \($0)" },
            secondary: (0..<80).map { "Secondary \($0)" }
        )
        XCTAssertEqual(values.count, 100)
        XCTAssertEqual(values.first, "Primary 0")
        XCTAssertEqual(values.last, "Secondary 19")
    }

    func testContextualStringsDeduplicateCaseInsensitively() {
        let values = VoiceSafetyPolicy.prioritizedContextualStrings(primary: ["Dorico", "dorico", "  "], secondary: ["DORICO", "Tie"])
        XCTAssertEqual(values, ["Dorico", "Tie"])
    }

    func testAudioFormatValidation() {
        XCTAssertTrue(VoiceSafetyPolicy.isValidAudioFormat(sampleRate: 48_000, channelCount: 1))
        XCTAssertFalse(VoiceSafetyPolicy.isValidAudioFormat(sampleRate: 0, channelCount: 1))
        XCTAssertFalse(VoiceSafetyPolicy.isValidAudioFormat(sampleRate: .nan, channelCount: 1))
        XCTAssertFalse(VoiceSafetyPolicy.isValidAudioFormat(sampleRate: 48_000, channelCount: 0))
    }

    func testUnknownSegmentsBlockExecution() {
        let batch = DoricoVoiceBatch(commands: [command("Undo")], unrecognizedSegments: ["spaceship"])
        XCTAssertThrowsError(try VoiceSafetyPolicy().executionPlan(for: batch, automatic: false)) {
            XCTAssertEqual($0 as? VoiceSafetyError, .containsUnknownSegments(["spaceship"]))
        }
    }

    func testLowConfidenceBlocksAutomaticExecution() {
        var value = command("Undo")
        value.confidence = 0.6
        XCTAssertThrowsError(try VoiceSafetyPolicy().executionPlan(for: DoricoVoiceBatch(commands: [value]), automatic: true)) {
            XCTAssertEqual($0 as? VoiceSafetyError, .lowConfidence(0.6))
        }
    }

    func testLowConfidenceCanBeManuallyReviewedAndRun() {
        var value = command("Undo")
        value.confidence = 0.6
        XCTAssertNoThrow(try VoiceSafetyPolicy().executionPlan(for: DoricoVoiceBatch(commands: [value]), automatic: false))
    }

    func testTooManyCommandsBlocked() {
        let batch = DoricoVoiceBatch(commands: (0..<25).map { _ in command("Undo") })
        XCTAssertThrowsError(try VoiceSafetyPolicy().executionPlan(for: batch, automatic: false))
    }

    func testTooManyRepeatedStepsBlocked() {
        let steps = (0..<65).map { _ in CommandStep(.keyChord(KeyChord("right"))) }
        let batch = DoricoVoiceBatch(commands: [DoricoVoiceCommand(label: "Repeat", canonicalPhrase: "repeat", action: .sequence(steps))])
        XCTAssertThrowsError(try VoiceSafetyPolicy().executionPlan(for: batch, automatic: false)) {
            XCTAssertEqual($0 as? VoiceSafetyError, .repeatLimitExceeded(65))
        }
    }

    func testLongTypedTextBlocked() {
        let batch = DoricoVoiceBatch(commands: [DoricoVoiceCommand(label: "Type", canonicalPhrase: "type", action: .typeText(String(repeating: "x", count: 257)))])
        XCTAssertThrowsError(try VoiceSafetyPolicy().executionPlan(for: batch, automatic: false))
    }

    func testInvalidDelayBlocked() {
        let action = CommandAction.sequence([CommandStep(.keyChord(KeyChord("a")), delayMilliseconds: 751)])
        let batch = DoricoVoiceBatch(commands: [DoricoVoiceCommand(label: "Bad", canonicalPhrase: "bad", action: action)])
        XCTAssertThrowsError(try VoiceSafetyPolicy().executionPlan(for: batch, automatic: false))
    }

    func testValidMultiCommandPlanFlattensInOrder() throws {
        let batch = DoricoVoiceLanguage.parseBatch("quarter note then C sharp four then tie")
        let plan = try VoiceSafetyPolicy().executionPlan(for: batch, automatic: false)
        XCTAssertEqual(plan.commands.map(\.label), ["Quarter note", "Enter C#4", "Tie"])
        XCTAssertEqual(plan.flattenedSteps.count, 3)
    }

    private func command(_ label: String) -> DoricoVoiceCommand {
        DoricoVoiceCommand(label: label, canonicalPhrase: label.lowercased(), action: .keyChord(KeyChord("z")))
    }
}

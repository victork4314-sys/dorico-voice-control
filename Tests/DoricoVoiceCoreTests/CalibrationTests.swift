import XCTest
@testable import DoricoVoiceCore

final class CalibrationTests: XCTestCase {
    func testCalibrationLearnsWholePhrase() {
        var profile = DoricoVoiceCalibrationProfile()
        profile.learn(expected: "quarter note", heard: "quarter nude")
        XCTAssertEqual(profile.apply(to: "quarter nude"), "quarter note")
        XCTAssertEqual(profile.completedPromptCount, 1)
    }

    func testCalibrationLearnsSafeTokenCorrection() {
        var profile = DoricoVoiceCalibrationProfile()
        profile.learn(expected: "add fortissimo", heard: "add forty see mo")
        XCTAssertEqual(profile.apply(to: "add forty see mo"), "add fortissimo")
    }

    func testCalibrationDoesNotReplaceUnsafeSingleWord() {
        var profile = DoricoVoiceCalibrationProfile()
        profile.learn(expected: "move right", heard: "move left")
        XCTAssertEqual(profile.apply(to: "left"), "left")
    }

    func testCalibrationCompletionIsBounded() {
        var profile = DoricoVoiceCalibrationProfile()
        for prompt in DoricoVoiceLanguage.calibrationPrompts + DoricoVoiceLanguage.calibrationPrompts {
            profile.learn(expected: prompt, heard: prompt)
        }
        XCTAssertEqual(profile.completedPromptCount, DoricoVoiceLanguage.calibrationPrompts.count)
        XCTAssertTrue(profile.isComplete)
    }

    func testReset() {
        var profile = DoricoVoiceCalibrationProfile()
        profile.learn(expected: "quarter note", heard: "quarter nude")
        profile.reset()
        XCTAssertEqual(profile.completedPromptCount, 0)
        XCTAssertTrue(profile.replacements.isEmpty)
        XCTAssertTrue(profile.phraseSamples.isEmpty)
    }
}

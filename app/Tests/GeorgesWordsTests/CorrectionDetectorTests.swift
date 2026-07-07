import XCTest
@testable import GeorgesWords

final class CorrectionDetectorTests: XCTestCase {

    func testDetectsMishearingFix() {
        let subs = CorrectionDetector.substitutions(
            from: "we should deploy coober netties on friday",
            to: "we should deploy Kubernetes on friday"
        )
        XCTAssertEqual(subs, [CorrectionDetector.Substitution(heard: "coober netties", corrected: "Kubernetes")])
    }

    func testIgnoresFullRewrite() {
        let subs = CorrectionDetector.substitutions(
            from: "hello world how are you",
            to: "totally different content over here now"
        )
        XCTAssertEqual(subs, [])
    }

    func testIgnoresWordingEdits() {
        // "very good" -> "quite nice" is a style change, not a mishearing:
        // the strings don't resemble each other.
        let subs = CorrectionDetector.substitutions(
            from: "this is very good stuff",
            to: "this is quite nice stuff"
        )
        XCTAssertEqual(subs, [])
    }

    func testIgnoresCaseOnlyChanges() {
        let subs = CorrectionDetector.substitutions(
            from: "i met george today",
            to: "i met George today"
        )
        XCTAssertEqual(subs, [])
    }

    func testIgnoresTrailingTyping() {
        // The user kept typing after the insertion — not corrections.
        let subs = CorrectionDetector.substitutions(
            from: "hello world",
            to: "hello world and some more thoughts here"
        )
        XCTAssertEqual(subs, [])
    }

    func testUnchangedTextLearnsNothing() {
        let subs = CorrectionDetector.substitutions(
            from: "nothing changed here at all",
            to: "nothing changed here at all"
        )
        XCTAssertEqual(subs, [])
    }

    // MARK: - Backlog 2.5 filter changes

    func testPhoneticSecondChance() {
        // "quay" → "key" fails plain letter distance (0.25) but is exactly
        // the sound-alike shape mishearings take — phonetics rescue it.
        let subs = CorrectionDetector.substitutions(
            from: "meet me at the quay tomorrow",
            to: "meet me at the key tomorrow"
        )
        XCTAssertEqual(subs, [CorrectionDetector.Substitution(heard: "quay", corrected: "key")])
    }

    func testPhoneticDoesNotRescueWordingEdits() {
        // Dissimilar in letters AND sound — stays a wording edit.
        let subs = CorrectionDetector.substitutions(
            from: "that was a strange meeting today",
            to: "that was a peculiar meeting today"
        )
        XCTAssertEqual(subs, [])
    }

    func testShortDictationHeavyFixLearnsInStrictMode() {
        // Two of four words fixed = under the 60% survival gate, but it's
        // one strong mishearing fix — strict mode must still learn it.
        let subs = CorrectionDetector.substitutions(
            from: "deploy coober netties now",
            to: "deploy Kubernetes now"
        )
        XCTAssertEqual(subs, [CorrectionDetector.Substitution(heard: "coober netties", corrected: "Kubernetes")])
    }

    func testStrictModeRejectsMultipleCandidates() {
        // Low survival AND several "fixes" = a rewrite wearing a costume.
        let subs = CorrectionDetector.substitutions(
            from: "alpha to beta",
            to: "alfa to betta"
        )
        XCTAssertEqual(subs, [])
    }
}

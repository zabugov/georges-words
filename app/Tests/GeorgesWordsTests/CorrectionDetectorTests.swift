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
}

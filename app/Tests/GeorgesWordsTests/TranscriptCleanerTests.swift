import XCTest
@testable import GeorgesWords

final class TranscriptCleanerTests: XCTestCase {

    private let cleaner = TranscriptCleaner()

    // MARK: - Fillers & tidy

    func testRemovesFillers() {
        XCTAssertEqual(cleaner.clean("um hello there", dictionary: []), "Hello there")
        XCTAssertEqual(cleaner.clean("i think uh we should go", dictionary: []), "I think we should go")
    }

    func testCapitalizesFirstLetter() {
        XCTAssertEqual(cleaner.clean("hello world", dictionary: []), "Hello world")
    }

    func testTidiesWhitespaceAndPunctuation() {
        XCTAssertEqual(cleaner.clean("hello   world , yes", dictionary: []), "Hello world, yes")
    }

    // MARK: - Dictionary

    func testEnforcesDictionarySpelling() {
        XCTAssertEqual(
            cleaner.clean("i love kubernetes", dictionary: ["Kubernetes"]),
            "I love Kubernetes"
        )
    }

    func testAppliesLearnedReplacements() {
        XCTAssertEqual(
            cleaner.clean(
                "coober netties is down",
                dictionary: ["Kubernetes"],
                replacements: [(heard: "coober netties", correct: "Kubernetes")]
            ),
            "Kubernetes is down"
        )
    }

    // MARK: - Numbers

    func testDigitAdjacentNumberForms() {
        XCTAssertEqual(cleaner.clean("it costs 50 percent more", dictionary: []), "It costs 50% more")
        XCTAssertEqual(cleaner.clean("give me 10 dollars", dictionary: []), "Give me $10")
    }

    func testSpelledOutNumberForms() {
        XCTAssertEqual(cleaner.clean("growth was twenty five percent", dictionary: []), "Growth was 25%")
        XCTAssertEqual(cleaner.clean("meet at three thirty pm", dictionary: []), "Meet at 3:30 PM")
    }

    // MARK: - Spoken commands (3.1)

    func testNewLineCommand() {
        XCTAssertEqual(
            cleaner.clean("first point new line second point", dictionary: []),
            "First point\nSecond point"
        )
    }

    func testNewParagraphCommand() {
        XCTAssertEqual(
            cleaner.clean("intro new paragraph body", dictionary: []),
            "Intro\n\nBody"
        )
    }

    func testQuoteCommand() {
        XCTAssertEqual(
            cleaner.clean("she said quote ship it end quote and left", dictionary: []),
            "She said \"ship it\" and left"
        )
    }

    func testArticleProtectsLiteralNewLine() {
        XCTAssertEqual(
            cleaner.clean("we need a new line of products", dictionary: []),
            "We need a new line of products"
        )
        XCTAssertEqual(
            cleaner.clean("the new line looks great", dictionary: []),
            "The new line looks great"
        )
    }
}

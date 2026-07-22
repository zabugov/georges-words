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

    func testCardinalNumbers() {
        XCTAssertEqual(cleaner.clean("give me one hundred dollars", dictionary: []), "Give me $100")
        XCTAssertEqual(cleaner.clean("we shipped two thousand units", dictionary: []), "We shipped 2000 units")
    }

    // MARK: - Phone numbers & emails

    func testPhoneNumberFormatting() {
        XCTAssertEqual(
            cleaner.clean("call me at five five five one two three four", dictionary: []),
            "Call me at 555-1234"
        )
        XCTAssertEqual(
            cleaner.clean("my number is eight zero zero five five five one two one two", dictionary: []),
            "My number is (800) 555-1212"
        )
    }

    func testEmailFormatting() {
        XCTAssertEqual(
            cleaner.clean("send it to john dot smith at gmail dot com", dictionary: []),
            "Send it to john.smith@gmail.com"
        )
    }

    func testLeadingEmailStaysLowercase() {
        XCTAssertEqual(
            cleaner.clean("jane at proton dot me is my address", dictionary: []),
            "jane@proton.me is my address"
        )
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

    // MARK: - Sound-alike dictionary matching (2026-07-22)

    func testPhoneticDictionaryFixesUnseenMisspellings() {
        // The six real-world ASR inventions for one unknown surname —
        // every one spelled differently, so exact mappings can't keep up.
        // The last two carry a stray "r" from clipped audio and exercise
        // the near-skeleton tier.
        for heard in ["Abagoff", "Abigoff", "Abakoff", "Abakov", "Abercov", "Abergoff"] {
            let out = cleaner.clean("hi my name is Zach \(heard)", dictionary: ["Zach Abugov"])
            XCTAssertEqual(out, "Hi my name is Zach Abugov", "\(heard) should become Abugov")
        }
    }

    func testPhoneticDictionaryLeavesOrdinaryWordsAlone() {
        let out = cleaner.clean("above the garage we keep a kayak and a backup bag", dictionary: ["Zach Abugov"])
        XCTAssertFalse(out.contains("Abugov"), "no ordinary word should turn into a name: \(out)")
    }

    func testPhoneticDictionaryDoesNotConvertRealNameSnaps() {
        // When the ASR snaps an unknown name to a REAL name it knows
        // ("Abugov" heard as "Abigail", 2026-07-22), the sound skeletons
        // genuinely differ (…l vs …v) and the phonetic pass must NOT
        // bridge that gap — loosening far enough to catch real-word
        // snaps converts ordinary words too. Real-word snaps are stable
        // spellings; the exact-mapping layer ("Abigail -> Abugov") is
        // the intended fix, and this test pins that boundary.
        let out = cleaner.clean("hi my name is Zach Abigail", dictionary: ["Zach Abugov"])
        XCTAssertEqual(out, "Hi my name is Zach Abigail")
        // With the mapping line, the exact layer handles it instead.
        let mapped = cleaner.clean(
            "hi my name is Zach Abigail",
            dictionary: ["Zach Abugov"],
            replacements: [(heard: "Abigail", correct: "Abugov")]
        )
        XCTAssertEqual(mapped, "Hi my name is Zach Abugov")
    }

    func testPhoneticDictionarySkipsShortTermsAndEmails() {
        // "Zach" (4 letters) is below the 5-letter target floor, and email
        // terms never become phonetic targets.
        let out = cleaner.clean("shack sack jack", dictionary: ["Zach", "zach@example.com"])
        XCTAssertEqual(out, "Shack sack jack")
    }
}

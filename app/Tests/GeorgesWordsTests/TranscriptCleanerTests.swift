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

    func testSpokenDecimalsJoinBeforeUnits() {
        // Owner report (2026-07-22): "…point 3 dollars" came out
        // "point $3" — the decimal must join before the unit rules run.
        XCTAssertEqual(
            cleaner.clean("that costs 126453 point 3 dollars", dictionary: []),
            "That costs $126453.3"
        )
        XCTAssertEqual(
            cleaner.clean("growth was 12 point 5 percent", dictionary: []),
            "Growth was 12.5%"
        )
        // "point" without digits on both sides is a word, not a decimal.
        XCTAssertEqual(
            cleaner.clean("i want to make a point 3 times", dictionary: []),
            "I want to make a point 3 times"
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

    func testPhoneticDictionaryNeverCorruptsRealEnglishWords() {
        // Common first names share consonant skeletons with everyday
        // words ("Lauren"/"learn", "David"/"devoid" are identical) — no
        // similarity threshold separates them. The system word list is
        // the guard (review finding, 2026-07-22).
        let cases: [(sentence: String, dictionary: [String])] = [
            ("i want to learn something new", ["Lauren"]),
            ("the room felt devoid of light", ["David"]),
            ("good morning everyone", ["Marina Cremonese"]),
            ("i am so sorry about that", ["Sarah"]),
        ]
        for entry in cases {
            let out = cleaner.clean(entry.sentence, dictionary: entry.dictionary)
            for name in entry.dictionary.flatMap({ $0.split(separator: " ") }) {
                XCTAssertFalse(
                    out.contains(String(name)),
                    "\(entry.dictionary) must not replace ordinary words: \(out)"
                )
            }
        }
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
        // "Zach" (4 letters) is below the 5-letter target floor, and a
        // full email address is never itself a sound-target (its short
        // name-part "zach" is below the floor too).
        let out = cleaner.clean("shack sack jack", dictionary: ["Zach", "zach@example.com"])
        XCTAssertEqual(out, "Shack sack jack")
    }

    func testDictionaryEmailReassemblesSplitName() {
        // The recognizer hears the name-part as separate words — it IS
        // the user's name — so only the last word reaches the @ and the
        // rest strands outside: "Zach abugov@gmail.com" (on-device,
        // 2026-07-22). The domain anchor folds it back together.
        XCTAssertEqual(
            cleaner.clean("email me at zach abugov at gmail dot com", dictionary: ["zachabugov@gmail.com"]),
            "Email me at zachabugov@gmail.com"
        )
        // Phonetic variant of the split pieces still folds.
        XCTAssertEqual(
            cleaner.clean("email me at zack abogov at gmail dot com", dictionary: ["zachabugov@gmail.com"]),
            "Email me at zachabugov@gmail.com"
        )
    }

    func testDictionaryEmailSurvivesInventedConsonants() {
        // Real on-device outputs for one address, dictated five times
        // (2026-07-22): split words, dropped h, and a stray l. All must
        // land on the dictionary address.
        for heard in [
            "sack abaclav at gmail dot com",
            "zacabugov at gmail dot com",
            "zach abugov at gmail dot com",
        ] {
            let out = cleaner.clean(heard, dictionary: ["zachabugov@gmail.com"])
            XCTAssertEqual(out, "zachabugov@gmail.com", "\(heard) should fold to the address")
        }
    }

    func testDictionaryEmailFoldsMinimally() {
        // Words ahead of an already-correct address must never be eaten
        // by the fold — smallest fold wins.
        XCTAssertEqual(
            cleaner.clean("email me at zachabugov at gmail dot com", dictionary: ["zachabugov@gmail.com"]),
            "Email me at zachabugov@gmail.com"
        )
    }

    func testDictionaryEmailLeavesOtherAddressesAlone() {
        // Same domain, different person — must never be folded or
        // rewritten into the dictionary address.
        XCTAssertEqual(
            cleaner.clean("email me at sarah at gmail dot com", dictionary: ["zachabugov@gmail.com"]),
            "Email me at sarah@gmail.com"
        )
    }

    func testPhoneticDictionaryFixesEmailNamePart() {
        // Real-world failures (2026-07-22): the spoken name-part of the
        // user's own email got mangled a new way each attempt, and the
        // exact mapping line couldn't keep up. The part before the @ is
        // a sound-target; SpokenContacts then assembles the address.
        for heard in ["zacapgov", "zacabogov"] {
            let out = cleaner.clean(
                "email me at \(heard) at gmail dot com",
                dictionary: ["zachabugov@gmail.com"]
            )
            XCTAssertEqual(out, "Email me at zachabugov@gmail.com", "\(heard) should snap to the address")
        }
        // The full address must never bleed into unrelated text.
        let untouched = cleaner.clean("email me when you land", dictionary: ["zachabugov@gmail.com"])
        XCTAssertEqual(untouched, "Email me when you land")
    }
}

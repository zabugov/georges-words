import XCTest
@testable import GeorgesWords

final class SnippetExpanderTests: XCTestCase {

    private let signOff = Snippet(trigger: "my sign off", expansion: "Best,\nZach")

    func testExpandsTrigger() {
        let result = SnippetExpander.apply([signOff], to: "ok my sign off")
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.text, "ok Best,\nZach")
    }

    func testMatchesDespiteTranscriptionPunctuation() {
        let result = SnippetExpander.apply([signOff], to: "ok, my sign off.")
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.text, "ok, Best,\nZach")
    }

    func testMatchesCaseInsensitively() {
        let result = SnippetExpander.apply([signOff], to: "My Sign Off")
        XCTAssertTrue(result.applied)
        XCTAssertEqual(result.text, "Best,\nZach")
    }

    func testNoMatchLeavesTextAlone() {
        let result = SnippetExpander.apply([signOff], to: "nothing to see here")
        XCTAssertFalse(result.applied)
        XCTAssertEqual(result.text, "nothing to see here")
    }

    func testEmptyExpansionNeverFires() {
        let empty = Snippet(trigger: "my sign off", expansion: "")
        let result = SnippetExpander.apply([empty], to: "ok my sign off")
        XCTAssertFalse(result.applied)
    }
}

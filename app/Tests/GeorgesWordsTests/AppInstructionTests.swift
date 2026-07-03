import XCTest
@testable import GeorgesWords

final class AppInstructionTests: XCTestCase {

    private let notes = [
        AppInstruction(appName: "Obsidian", bundleID: "md.obsidian", instruction: "use markdown headings"),
        AppInstruction(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", instruction: "keep it terse"),
        AppInstruction(appName: "Empty", bundleID: "com.example.empty", instruction: "   "),
    ]

    func testMatchesByBundleIDSubstring() {
        XCTAssertEqual(
            AppSettings.matchInstruction(notes, bundleID: "md.obsidian"),
            "use markdown headings"
        )
        XCTAssertEqual(
            AppSettings.matchInstruction(notes, bundleID: "com.tinyspeck.slackmacgap"),
            "keep it terse"
        )
    }

    func testMatchIsCaseInsensitive() {
        XCTAssertEqual(
            AppSettings.matchInstruction(notes, bundleID: "MD.Obsidian"),
            "use markdown headings"
        )
    }

    func testNoMatchForUnknownApp() {
        XCTAssertNil(AppSettings.matchInstruction(notes, bundleID: "com.apple.mail"))
        XCTAssertNil(AppSettings.matchInstruction(notes, bundleID: ""))
    }

    func testBlankInstructionNeverMatches() {
        XCTAssertNil(AppSettings.matchInstruction(notes, bundleID: "com.example.empty"))
    }
}

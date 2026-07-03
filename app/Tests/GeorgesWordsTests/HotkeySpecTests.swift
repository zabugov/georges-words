import XCTest
@testable import GeorgesWords

final class HotkeySpecTests: XCTestCase {

    func testLegacyMigration() {
        XCTAssertEqual(HotkeySpec.legacy("fn"), .fn)
        XCTAssertEqual(HotkeySpec.legacy("rightCommand"), .rightCommand)
        XCTAssertEqual(HotkeySpec.legacy("rightOption"), .rightOption)
        XCTAssertNil(HotkeySpec.legacy("something else"))
        XCTAssertNil(HotkeySpec.legacy(nil))
    }

    func testEqualityIsByPhysicalKey() {
        let renamed = HotkeySpec(keyCode: 63, modifierFlagRawValue: nil, displayName: "Globe")
        XCTAssertEqual(renamed, .fn)
        XCTAssertNotEqual(HotkeySpec.fn, .rightCommand)
    }

    func testCodableRoundTrip() throws {
        let original = HotkeySpec(keyCode: 96, modifierFlagRawValue: nil, displayName: "F5")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeySpec.self, from: data)
        XCTAssertEqual(decoded.keyCode, original.keyCode)
        XCTAssertNil(decoded.modifierFlagRawValue)
        XCTAssertEqual(decoded.displayName, "F5")
    }

    func testModifierFlagBridging() {
        XCTAssertEqual(HotkeySpec.fn.modifierFlag, .function)
        XCTAssertNil(HotkeySpec(keyCode: 96, modifierFlagRawValue: nil, displayName: "F5").modifierFlag)
    }
}

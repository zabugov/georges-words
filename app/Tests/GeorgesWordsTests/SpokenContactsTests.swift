import XCTest
@testable import GeorgesWords

final class SpokenContactsTests: XCTestCase {

    // MARK: - Email

    func testSimpleEmail() {
        XCTAssertEqual(SpokenContacts.normalize("email me at john at gmail dot com"),
                       "email me at john@gmail.com")
    }

    func testEmailWithDottedLocalPart() {
        XCTAssertEqual(SpokenContacts.normalize("jane dot doe at proton dot me"),
                       "jane.doe@proton.me")
    }

    func testEmailWithSubdomainTLD() {
        XCTAssertEqual(SpokenContacts.normalize("send to john dot smith at company dot co dot uk"),
                       "send to john.smith@company.co.uk")
    }

    func testEmailWithUnderscoreAndDash() {
        XCTAssertEqual(SpokenContacts.normalize("jane underscore doe at my dash host dot org"),
                       "jane_doe@my-host.org")
    }

    func testEmailLowercasesInput() {
        XCTAssertEqual(SpokenContacts.normalize("John at Gmail dot Com"), "john@gmail.com")
    }

    func testEmailKeepsTrailingSentencePeriod() {
        XCTAssertEqual(SpokenContacts.normalize("reach me at bob at example dot com."),
                       "reach me at bob@example.com.")
    }

    func testUnknownTLDLeftAlone() {
        // "office" is not a valid TLD → not an address.
        XCTAssertEqual(SpokenContacts.normalize("meet at noon dot the office"),
                       "meet at noon dot the office")
    }

    func testPronounDomainLeftAlone() {
        XCTAssertEqual(SpokenContacts.normalize("look at this dot org file"),
                       "look at this dot org file")
    }

    func testBuildEmailValidation() {
        XCTAssertEqual(SpokenContacts.buildEmail(local: "john", domain: "gmail dot com"), "john@gmail.com")
        XCTAssertNil(SpokenContacts.buildEmail(local: "john", domain: "gmail"))          // no dot
        XCTAssertNil(SpokenContacts.buildEmail(local: "", domain: "gmail dot com"))      // empty local
    }

    // MARK: - Phone (spoken digit words)

    func testSevenDigitPhone() {
        XCTAssertEqual(SpokenContacts.normalize("call five five five one two three four"),
                       "call 555-1234")
    }

    func testTenDigitPhone() {
        XCTAssertEqual(SpokenContacts.normalize("my number is eight zero zero five five five one two one two"),
                       "my number is (800) 555-1212")
    }

    func testElevenDigitPhoneWithCountryCode() {
        XCTAssertEqual(SpokenContacts.normalize("one eight zero zero five five five one two one two"),
                       "+1 (800) 555-1212")
    }

    func testOhReadsAsZero() {
        XCTAssertEqual(SpokenContacts.normalize("area code five five five oh one two three"),
                       "area code 555-0123")
    }

    func testDoubleAndTripleExpansion() {
        // "five five five triple one two" → 5 5 5 1 1 1 2 = 7 digits.
        XCTAssertEqual(SpokenContacts.normalize("five five five triple one two"),
                       "555-1112")
    }

    func testShortDigitRunLeftAlone() {
        // Only three number words — not a phone number.
        XCTAssertEqual(SpokenContacts.normalize("one two three go"), "one two three go")
    }

    // MARK: - Phone (already-grouped digits)

    func testGroupedDigitsCanonicalized() {
        XCTAssertEqual(SpokenContacts.normalize("call 800 555 1212"), "call (800) 555-1212")
    }

    func testGroupedDigitsWithCountryCode() {
        XCTAssertEqual(SpokenContacts.normalize("1-800-555-1212"), "+1 (800) 555-1212")
        XCTAssertEqual(SpokenContacts.normalize("+1 800.555.1212"), "+1 (800) 555-1212")
    }

    func testBareTenDigitIdLeftAlone() {
        // No separators → could be an order number, so leave it.
        XCTAssertEqual(SpokenContacts.normalize("order 8005551212 shipped"),
                       "order 8005551212 shipped")
    }

    func testFormatPhoneLengths() {
        XCTAssertEqual(SpokenContacts.formatPhone("5551234"), "555-1234")
        XCTAssertEqual(SpokenContacts.formatPhone("8005551212"), "(800) 555-1212")
        XCTAssertEqual(SpokenContacts.formatPhone("18005551212"), "+1 (800) 555-1212")
        XCTAssertNil(SpokenContacts.formatPhone("12345"))
    }
}

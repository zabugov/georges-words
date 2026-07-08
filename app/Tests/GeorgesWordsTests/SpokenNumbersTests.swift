import XCTest
@testable import GeorgesWords

final class SpokenNumbersTests: XCTestCase {

    func testValueParsing() {
        XCTAssertEqual(SpokenNumbers.value(of: "zero"), 0)
        XCTAssertEqual(SpokenNumbers.value(of: "seven"), 7)
        XCTAssertEqual(SpokenNumbers.value(of: "twelve"), 12)
        XCTAssertEqual(SpokenNumbers.value(of: "twenty"), 20)
        XCTAssertEqual(SpokenNumbers.value(of: "twenty five"), 25)
        XCTAssertEqual(SpokenNumbers.value(of: "forty-two"), 42)
        XCTAssertEqual(SpokenNumbers.value(of: "Ninety Nine"), 99)
        XCTAssertNil(SpokenNumbers.value(of: "banana"))
        XCTAssertNil(SpokenNumbers.value(of: "twenty twelve"))
    }

    func testUnitNormalization() {
        XCTAssertEqual(SpokenNumbers.normalize("ten percent"), "10%")
        XCTAssertEqual(SpokenNumbers.normalize("about twenty five percent there"), "about 25% there")
        XCTAssertEqual(SpokenNumbers.normalize("five dollars"), "$5")
        XCTAssertEqual(SpokenNumbers.normalize("thirty degrees"), "30°")
    }

    func testTimeNormalization() {
        XCTAssertEqual(SpokenNumbers.normalize("three thirty pm"), "3:30 PM")
        XCTAssertEqual(SpokenNumbers.normalize("seven pm"), "7 PM")
        XCTAssertEqual(SpokenNumbers.normalize("nine oh five am"), "9:05 AM")
        XCTAssertEqual(SpokenNumbers.normalize("ten fifteen a.m."), "10:15 AM")
        XCTAssertEqual(SpokenNumbers.normalize("seven forty five pm"), "7:45 PM")
    }

    func testAmbiguousFormsLeftAlone() {
        // No am/pm → not clearly a time.
        XCTAssertEqual(SpokenNumbers.normalize("five thirty sounds fine"), "five thirty sounds fine")
        // Prose numbers without a unit stay as spoken.
        XCTAssertEqual(SpokenNumbers.normalize("one of those days"), "one of those days")
    }

    // MARK: - Cardinals (magnitude numbers)

    func testCardinalValueParsing() {
        XCTAssertEqual(SpokenNumbers.cardinalValue(of: "one hundred twenty three"), 123)
        XCTAssertEqual(SpokenNumbers.cardinalValue(of: "one thousand two hundred"), 1200)
        XCTAssertEqual(SpokenNumbers.cardinalValue(of: "two thousand twenty six"), 2026)
        XCTAssertEqual(SpokenNumbers.cardinalValue(of: "five million"), 5_000_000)
        XCTAssertEqual(SpokenNumbers.cardinalValue(of: "fifteen"), 15)
        XCTAssertNil(SpokenNumbers.cardinalValue(of: "banana"))
    }

    func testCardinalNormalization() {
        XCTAssertEqual(SpokenNumbers.normalize("we sold one hundred twenty three units"),
                       "we sold 123 units")
        XCTAssertEqual(SpokenNumbers.normalize("about two thousand people"), "about 2000 people")
        XCTAssertEqual(SpokenNumbers.normalize("the year two thousand twenty six"), "the year 2026")
    }

    func testCardinalsLeaveSmallAndIdiomaticFormsAlone() {
        // No magnitude word → small counts stay as words.
        XCTAssertEqual(SpokenNumbers.normalize("twenty five people"), "twenty five people")
        // Bare scale word with no number → idioms survive.
        XCTAssertEqual(SpokenNumbers.normalize("thanks a million"), "thanks a million")
        XCTAssertEqual(SpokenNumbers.normalize("hundred people showed up"), "hundred people showed up")
    }
}

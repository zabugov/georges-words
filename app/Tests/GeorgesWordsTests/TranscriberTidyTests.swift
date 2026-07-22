import XCTest
@testable import GeorgesWords

final class TranscriberTidyTests: XCTestCase {

    func testKnownNonSpeechMarkersAreRemoved() {
        XCTAssertEqual(Transcriber.tidy("[BLANK_AUDIO]"), "")
        XCTAssertEqual(Transcriber.tidy("hello (music) world"), "hello world")
        XCTAssertEqual(Transcriber.tidy("so [ typing ] anyway"), "so anyway")
        XCTAssertEqual(Transcriber.tidy("<|startoftranscript|>hi there"), "hi there")
    }

    func testDictatedParentheticalsSurvive() {
        // Real content in brackets must never be treated as an ASR
        // artifact (review P2, 2026-07-22).
        XCTAssertEqual(Transcriber.tidy("the plan (draft) is attached"),
                       "the plan (draft) is attached")
        XCTAssertEqual(Transcriber.tidy("bring the form [optional] tomorrow"),
                       "bring the form [optional] tomorrow")
        XCTAssertEqual(Transcriber.tidy("we won (finally) after two years"),
                       "we won (finally) after two years")
    }
}

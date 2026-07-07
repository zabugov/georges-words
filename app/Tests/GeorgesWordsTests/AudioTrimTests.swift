import XCTest
@testable import GeorgesWords

final class AudioTrimTests: XCTestCase {

    func testNearSilenceOnQuietBuffer() {
        let quiet = [Float](repeating: 0.001, count: 11_200) // 0.7 s of hiss
        XCTAssertTrue(AudioTrim.isNearSilence(quiet))
    }

    func testSpeechIsNotNearSilence() {
        // Typical speech RMS is ~0.01–0.2 (see AudioRecorder.append).
        let speech = (0..<11_200).map { Float(sin(Double($0) * 0.3)) * 0.05 }
        XCTAssertFalse(AudioTrim.isNearSilence(speech))
    }

    func testEmptyBufferCountsAsSilence() {
        XCTAssertTrue(AudioTrim.isNearSilence([]))
    }

    func testTrimKeepsSpeechAndPadding() {
        // 1 s silence + 1 s tone + 1 s silence → trimmed to tone ± 0.15 s.
        var samples = [Float](repeating: 0, count: 16_000)
        samples += [Float](repeating: 0.1, count: 16_000)
        samples += [Float](repeating: 0, count: 16_000)
        let trimmed = AudioTrim.trimSilence(samples)
        XCTAssertEqual(trimmed.count, 16_000 + 2 * 2_400)
    }

    func testTrimOfPureSilenceIsEmpty() {
        XCTAssertEqual(AudioTrim.trimSilence([Float](repeating: 0, count: 8_000)), [])
    }
}

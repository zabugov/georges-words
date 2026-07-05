import XCTest
@testable import GeorgesWords

final class ManagedOllamaTests: XCTestCase {

    func testPullPercentParsing() {
        XCTAssertEqual(
            ManagedOllama.pullPercent(fromLine: #"{"status":"pulling abc","total":1000,"completed":500}"#),
            50
        )
        XCTAssertEqual(
            ManagedOllama.pullPercent(fromLine: #"{"status":"pulling abc","total":3,"completed":3}"#),
            100
        )
    }

    func testPullPercentIgnoresLinesWithoutTotals() {
        XCTAssertNil(ManagedOllama.pullPercent(fromLine: #"{"status":"verifying sha256 digest"}"#))
        XCTAssertNil(ManagedOllama.pullPercent(fromLine: #"{"status":"pulling","total":0,"completed":0}"#))
        XCTAssertNil(ManagedOllama.pullPercent(fromLine: "not json at all"))
        XCTAssertNil(ManagedOllama.pullPercent(fromLine: ""))
    }

    func testPullPercentClampsOvershoot() {
        XCTAssertEqual(
            ManagedOllama.pullPercent(fromLine: #"{"total":1000,"completed":2000}"#),
            100
        )
    }

    func testPullErrorParsing() {
        XCTAssertEqual(
            ManagedOllama.pullError(fromLine: #"{"error":"pull model manifest: file does not exist"}"#),
            "pull model manifest: file does not exist"
        )
        XCTAssertNil(ManagedOllama.pullError(fromLine: #"{"status":"success"}"#))
        XCTAssertNil(ManagedOllama.pullError(fromLine: "garbage"))
    }

    func testSHA256MatchesKnownDigest() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("gw-sha-test-\(UUID().uuidString)")
        try Data("hello\n".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(
            try ManagedOllama.sha256(of: file),
            "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"
        )
    }

    func testPinnedEngineDigestLooksLikeSHA256() {
        XCTAssertEqual(ManagedOllama.engineSHA256.count, 64)
        XCTAssertTrue(ManagedOllama.engineSHA256.allSatisfy(\.isHexDigit))
        XCTAssertTrue(ManagedOllama.engineDownloadURL.absoluteString.contains(ManagedOllama.engineVersion))
    }
}

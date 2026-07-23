import Foundation

/// The macOS system word list (~235k entries), lowercased, loaded once.
/// Two consumers: phonetic dictionary matching treats these words as
/// off-limits for snapping (real words are never "corrected" into
/// names), and spoken-email assembly treats a common-word local part
/// as weak evidence ("look at gmail dot com" is prose, not an address).
///
/// If the list can't be read, `all` is empty — each consumer decides
/// its own safe direction for that case (the phonetic matcher fails
/// CLOSED and skips fuzzy matching entirely).
enum SystemWords {
    static let all: Set<String> = {
        guard let contents = try? String(contentsOfFile: "/usr/share/dict/words", encoding: .utf8) else {
            return []
        }
        var words = Set<String>()
        for line in contents.split(separator: "\n") where line.count >= 4 {
            words.insert(line.lowercased())
        }
        return words
    }()
}

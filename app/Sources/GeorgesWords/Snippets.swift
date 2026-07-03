import Foundation

/// A voice shortcut: say the trigger phrase, get the expansion text.
struct Snippet: Codable, Identifiable, Equatable {
    var id = UUID()
    var trigger: String
    var expansion: String
}

enum SnippetExpander {

    /// Replaces trigger phrases with their expansions. Matching is
    /// case-insensitive and tolerant of the punctuation the transcriber
    /// sprinkles between words ("email, sign off." still matches
    /// "email sign off"). Returns the new text and whether anything fired.
    static func apply(_ snippets: [Snippet], to text: String) -> (text: String, applied: Bool) {
        var result = text
        var applied = false

        for snippet in snippets {
            let words = snippet.trigger
                .split(separator: " ")
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            guard !words.isEmpty, !snippet.expansion.isEmpty else { continue }

            let pattern = #"\b"# + words.joined(separator: #"[\s,]+"#) + #"\b[.!?,]?"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }

            let range = NSRange(result.startIndex..., in: result)
            if regex.firstMatch(in: result, range: range) != nil {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: range,
                    withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion)
                )
                applied = true
            }
        }
        return (result, applied)
    }
}

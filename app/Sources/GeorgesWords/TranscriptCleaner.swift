import Foundation

/// Stage 1 of formatting: fast, deterministic, rule-based cleanup.
/// Always runs, costs ~0 ms, and is the final output whenever the LLM
/// stage is disabled or unavailable.
struct TranscriptCleaner {

    private static let fillerPattern = try! NSRegularExpression(
        pattern: #"(?<=^|[\s,.])(um+|uh+|uhm|erm|mhm|hmm)[,.]?(?=[\s,.]|$)"#,
        options: [.caseInsensitive]
    )

    func clean(_ text: String, dictionary: [String], replacements: [(heard: String, correct: String)] = []) -> String {
        var result = text

        result = Self.fillerPattern.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: ""
        )

        // Learned mishearing fixes: "coober netties" -> "Kubernetes".
        for replacement in replacements {
            let escaped = NSRegularExpression.escapedPattern(for: replacement.heard)
            guard let regex = try? NSRegularExpression(pattern: #"\b\#(escaped)\b"#, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement.correct)
            )
        }

        // Enforce the exact spelling/casing of personal dictionary terms.
        for term in dictionary where !term.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            guard let regex = try? NSRegularExpression(pattern: #"\b\#(escaped)\b"#, options: [.caseInsensitive]) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: term)
            )
        }

        // Common spoken-number forms.
        result = result.replacingOccurrences(of: #"(\d+)\s+percent\b"#, with: "$1%", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(\d+)\s+dollars\b"#, with: "\\$$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(\d+)\s+degrees\b"#, with: "$1°", options: .regularExpression)

        // Spelled-out numbers: "twenty five percent", "three thirty pm".
        result = SpokenNumbers.normalize(result)

        // Tidy whitespace: collapse runs, remove space before punctuation.
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize the first letter.
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }

        // Spoken control commands, last so line breaks survive the
        // whitespace tidy above.
        result = Self.applySpokenCommands(result)

        return result
    }

    // MARK: - Spoken control commands (backlog 3.1)

    /// "new line", "new paragraph", and "quote … end quote" — handled
    /// deterministically, never left to the LLM. Article-protected:
    /// "a new line of products" is left alone.
    static func applySpokenCommands(_ text: String) -> String {
        var result = text
        var applied = false

        // "quote … end quote" → "…"
        let quotePattern = #"\bquote[,.]?\s+(.+?)[,.]?\s+end quote\b"#
        if let regex = try? NSRegularExpression(pattern: quotePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(result.startIndex..., in: result)
            if regex.firstMatch(in: result, range: range) != nil {
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\"$1\"")
                applied = true
            }
        }

        // "new paragraph" → blank line, "new line" → line break. The
        // lookbehinds keep "a new line of products" intact.
        let breaks: [(pattern: String, replacement: String)] = [
            (#"\s*(?<!\ba\s)(?<!\bthe\s)\bnew\s+paragraph\b[,.;:]?\s*"#, "\n\n"),
            (#"\s*(?<!\ba\s)(?<!\bthe\s)\b(?:new\s+line|newline)\b[,.;:]?\s*"#, "\n"),
        ]
        for entry in breaks {
            guard let regex = try? NSRegularExpression(pattern: entry.pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            if regex.firstMatch(in: result, range: range) != nil {
                result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: entry.replacement)
                applied = true
            }
        }

        guard applied else { return result }
        return Self.capitalizeAfterBreaks(result.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Each line after an inserted break starts with a capital.
    private static func capitalizeAfterBreaks(_ text: String) -> String {
        var output = ""
        var capitalizeNext = false
        for character in text {
            if character.isNewline {
                capitalizeNext = true
                output.append(character)
                continue
            }
            if capitalizeNext, character.isLetter {
                output.append(contentsOf: character.uppercased())
                capitalizeNext = false
            } else {
                if capitalizeNext, !character.isWhitespace { capitalizeNext = false }
                output.append(character)
            }
        }
        return output
    }
}

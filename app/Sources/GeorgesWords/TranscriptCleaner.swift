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

        // Tidy whitespace: collapse runs, remove space before punctuation.
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize the first letter.
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return result
    }
}

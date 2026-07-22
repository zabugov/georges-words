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

        // Sound-alike dictionary matching (2026-07-22): the ASR invents a
        // NEW misspelling of an unknown name every time — "Abagoff",
        // "Abigoff", "Abakov" for "Abugov" — so exact heard -> correct
        // lines can never keep up. Any word that clearly SOUNDS like a
        // dictionary word becomes that word. Conservative on purpose
        // (skeleton AND letter similarity must both agree): a wrong swap
        // here would corrupt silently.
        result = Self.applyPhoneticDictionary(result, dictionary: dictionary)

        // Phone numbers and emails: "five five five one two three four" →
        // "555-1234", "john at gmail dot com" → "john@gmail.com".
        result = SpokenContacts.normalize(result)

        // Spelled-out numbers: "twenty five percent", "three thirty pm",
        // "one hundred twenty three" → "123". Runs before the digit-adjacent
        // rules below so cardinals like "five hundred dollars" → "500 dollars"
        // get the "$" treatment too.
        result = SpokenNumbers.normalize(result)

        // Digit-adjacent spoken-number forms.
        result = result.replacingOccurrences(of: #"(\d+)\s+percent\b"#, with: "$1%", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(\d+)\s+dollars\b"#, with: "\\$$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(\d+)\s+degrees\b"#, with: "$1°", options: .regularExpression)

        // Tidy whitespace: collapse runs, remove space before punctuation.
        result = result.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Capitalize the first letter — unless the transcript opens with an
        // email address, which must stay lowercase.
        let firstToken = result.prefix { !$0.isWhitespace }
        if let first = result.first, first.isLowercase, !firstToken.contains("@") {
            result = first.uppercased() + result.dropFirst()
        }

        // Spoken control commands, last so line breaks survive the
        // whitespace tidy above.
        result = Self.applySpokenCommands(result)

        return result
    }

    // MARK: - Sound-alike dictionary matching

    /// Replace transcript words that sound like a dictionary word with
    /// that word's exact spelling. Gates: only dictionary words of 5+
    /// letters become targets (short words collide phonetically), the
    /// transcript word must have 4+ letters, and BOTH the consonant
    /// skeleton must match exactly AND the letter similarity must reach
    /// 0.40 (real-world calibration: "Abakoff" → "Abugov" sits at 0.43;
    /// the skeleton equality is the primary gate, the letter floor only
    /// blocks coincidental skeleton collisions). Multi-word terms
    /// contribute their individual words.
    static func applyPhoneticDictionary(_ text: String, dictionary: [String]) -> String {
        var targets: [(word: String, key: String)] = []
        var dictionaryWords = Set<String>()
        for term in dictionary where !term.contains("@") {
            for part in term.split(separator: " ") {
                let target = String(part)
                let lower = target.lowercased()
                guard dictionaryWords.insert(lower).inserted else { continue }
                guard target.count >= 5, target.first?.isLetter == true else { continue }
                targets.append((target, Phonetics.key(lower)))
            }
        }
        guard !targets.isEmpty else { return text }
        guard let wordRegex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z']*"#) else { return text }

        var result = text
        // Back to front so earlier ranges stay valid as we edit.
        let matches = wordRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            let word = (result as NSString).substring(with: match.range)
            let lower = word.lowercased()
            guard lower.count >= 4, !dictionaryWords.contains(lower) else { continue }
            let key = Phonetics.key(lower)
            for target in targets where key == target.key
                && Phonetics.similarity(lower, target.word.lowercased()) >= 0.40 {
                result = (result as NSString).replacingCharacters(in: match.range, with: target.word)
                break
            }
        }
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

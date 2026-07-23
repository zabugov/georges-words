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

        // Dictionary emails, final assembly: the recognizer often hears
        // the name-part as SEPARATE words ("zachabugov" → "Zach
        // Abugov"), so only the last word reaches the @ and the rest
        // strands outside — "Zach abugov@gmail.com" (on-device,
        // 2026-07-22). With the exact domain as the anchor, fold the
        // stranded words back in and snap to the dictionary address.
        result = Self.applyDictionaryEmails(result, dictionary: dictionary)

        // Spelled-out numbers: "twenty five percent", "three thirty pm",
        // "one hundred twenty three" → "123". Runs before the digit-adjacent
        // rules below so cardinals like "five hundred dollars" → "500 dollars"
        // get the "$" treatment too.
        result = SpokenNumbers.normalize(result)

        // Digit-adjacent spoken-number forms. Spoken decimals join FIRST
        // ("126,453 point 3" → "126,453.3") so the unit rules below see
        // the whole number — otherwise "point 3 dollars" came out
        // "point $3" (owner report, 2026-07-22). Numbers may carry
        // thousands separators from the cardinal pass, so every rule
        // accepts them.
        let integer = #"(?:\d{1,3}(?:,\d{3})+|\d+)"#
        result = result.replacingOccurrences(of: #"(?i)("# + integer + #")\s+point\s+(\d+)"#, with: "$1.$2", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)("# + integer + #"(?:\.\d+)?)\s+percent\b"#, with: "$1%", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)("# + integer + #"(?:\.\d+)?)\s+dollars\b"#, with: "\\$$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"(?i)("# + integer + #"(?:\.\d+)?)\s+degrees\b"#, with: "$1°", options: .regularExpression)

        // Large dollar amounts read with thousands separators —
        // "$2,756,243.7", not "$2756243.7" (owner report, 2026-07-23).
        // Only money is grouped here: bare digit runs can be IDs.
        if let dollarRegex = try? NSRegularExpression(pattern: #"\$(\d{5,})"#) {
            let matches = dollarRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                let ns = result as NSString
                var out: [Character] = []
                for (index, digit) in ns.substring(with: match.range(at: 1)).reversed().enumerated() {
                    if index > 0 && index % 3 == 0 { out.append(",") }
                    out.append(digit)
                }
                result = ns.replacingCharacters(in: match.range, with: "$" + String(out.reversed()))
            }
        }

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
    /// that word's exact spelling. Gates (calibrated on the real-world
    /// "Abugov" variant set, 2026-07-22): only dictionary words of 5+
    /// letters become targets (short words collide phonetically), the
    /// transcript word must have 4+ letters, and then EITHER
    /// - the consonant skeletons match exactly and letter similarity is
    ///   ≥ 0.40 ("Abakoff" sits at 0.43), OR
    /// - the word's skeleton contains the whole target skeleton in order
    ///   with at most one inserted consonant (clipped audio inserts
    ///   strays: "Abercov", "Abergoff") and letter similarity is ≥ 0.50.
    /// Multi-word terms contribute their individual words.
    ///
    /// The overriding guard: a word the system word list knows is NEVER
    /// snapped. With `Lauren` in the dictionary, "learn" has the identical
    /// consonant skeleton and 0.67 letter similarity — no threshold
    /// separates them (review finding, 2026-07-22). Misheard names are
    /// exactly the words that AREN'T real words ("Abakoff", "Cremoneza"),
    /// so the guard costs nothing; a mishearing that lands ON a real word
    /// ("Abigail") was already out of phonetic reach by design and stays
    /// the job of an exact `heard -> Correct` mapping.
    static func applyPhoneticDictionary(_ text: String, dictionary: [String]) -> String {
        var targets: [(word: String, key: String)] = []
        var dictionaryWords = Set<String>()
        func addTarget(_ target: String) {
            // Latinized on both sides: a homoglyph in the stored line
            // (or in the transcript) must never break matching, and the
            // replacement written out is always the clean Latin form.
            let clean = Phonetics.latinize(target)
            let lower = clean.lowercased()
            guard dictionaryWords.insert(lower).inserted else { return }
            guard clean.count >= 5, clean.first?.isLetter == true else { return }
            targets.append((clean, Phonetics.key(lower)))
        }
        for term in dictionary {
            if term.contains("@") {
                // Email terms: the full address is never a sound-target,
                // but the name-part before the @ is exactly what people
                // dictate ("zachabugov at gmail dot com") and gets
                // mangled like any unknown name. Its letter-fragments
                // become targets so the spelling snaps right before
                // SpokenContacts assembles the address (2026-07-22).
                // The address is the last @-carrying token, so a
                // decorated line can't leak its label words in.
                guard let address = term.split(whereSeparator: { $0.isWhitespace })
                    .last(where: { $0.contains("@") }),
                      let atIndex = address.firstIndex(of: "@")
                else { continue }
                for fragment in address[..<atIndex].split(whereSeparator: { !$0.isLetter }) {
                    addTarget(String(fragment))
                }
            } else {
                for part in term.split(separator: " ") {
                    addTarget(String(part))
                }
            }
        }
        guard !targets.isEmpty else { return text }
        // Fail CLOSED: without the word list there is no safe way to
        // fuzzy-match — skip snapping entirely rather than silently
        // fall back to corrupting prose (review follow-up, 2026-07-22).
        guard !SystemWords.all.isEmpty else { return text }
        guard let wordRegex = try? NSRegularExpression(pattern: #"[A-Za-z][A-Za-z']*"#) else { return text }

        var result = text
        // Back to front so earlier ranges stay valid as we edit.
        let matches = wordRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            let word = (result as NSString).substring(with: match.range)
            let lower = Phonetics.latinize(word.lowercased())
            guard lower.count >= 4, !dictionaryWords.contains(lower) else { continue }
            guard !SystemWords.all.contains(lower) else { continue }
            let key = Phonetics.key(lower)
            for target in targets {
                let letterSimilarity = Phonetics.similarity(lower, target.word.lowercased())
                // Near tier: clipped audio INSERTS stray consonants, so the
                // word's skeleton must still contain the whole target
                // skeleton in order, with at most one extra. A MISSING
                // consonant ("above" → "apf" has no k) is a different word
                // — CI caught exactly that false positive (2026-07-22).
                let nearSkeleton = key.count <= target.key.count + 1
                    && Phonetics.containsInOrder(target.key, in: key)
                let matches = (key == target.key && letterSimilarity >= 0.40)
                    || (nearSkeleton && letterSimilarity >= 0.50)
                guard matches else { continue }
                result = (result as NSString).replacingCharacters(in: match.range, with: target.word)
                break
            }
        }
        return result
    }

    // MARK: - Dictionary email assembly

    /// Snap `… Zach abugov@gmail.com` to `… zachabugov@gmail.com` when
    /// the dictionary holds an address at that exact domain. Up to two
    /// words immediately before the local part are candidates for
    /// folding in; the joined result must match the dictionary's
    /// name-part by spelling or by sound. The exact-domain anchor is
    /// what makes this safe: an unrelated `sarah@gmail.com` never
    /// sounds like the dictionary name-part, so it survives untouched.
    static func applyDictionaryEmails(_ text: String, dictionary: [String]) -> String {
        var result = text
        for term in dictionary {
            // Tolerate decoration on the line ("work: zachabugov@…"):
            // the address is the last @-carrying token.
            guard let address = term.split(whereSeparator: { $0.isWhitespace })
                .last(where: { $0.contains("@") })
                .map(String.init)
            else { continue }
            // A line dictated/pasted through the recognizer can carry
            // Cyrillic lookalikes that make every comparison fail while
            // LOOKING perfect — normalize, and say so in the log.
            if address.contains(where: { !$0.isASCII }) {
                DebugLog.log("Email fold: dictionary address contains non-Latin lookalike characters — normalizing (retype the line by keyboard to fix permanently)")
            }
            let cleanAddress = Phonetics.latinize(address)
            let parts = cleanAddress.split(separator: "@", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let dictLocal = parts[0].lowercased().filter(\.isLetter)
            let dictKey = Phonetics.key(dictLocal)
            let domain = String(parts[1])
            guard dictLocal.count >= 4, !domain.isEmpty else { continue }

            let pattern = #"((?:[A-Za-z][A-Za-z']*\s+){0,2})([A-Za-z0-9._-]+)@"#
                + NSRegularExpression.escapedPattern(for: domain)
                + #"(?![A-Za-z0-9-])"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }

            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                let ns = result as NSString
                let words = ns.substring(with: match.range(at: 1))
                    .split(whereSeparator: { $0.isWhitespace }).map(String.init)
                let local = ns.substring(with: match.range(at: 2))
                // SMALLEST fold first — consume preceding words only when
                // the local part alone doesn't already match; unrelated
                // words ahead of a correct address must never be eaten.
                var foldFrom: Int?
                for start in stride(from: words.count, through: 0, by: -1) {
                    let joined = Phonetics.latinize((words[start...].joined() + local).lowercased())
                        .filter(\.isLetter)
                    let joinedKey = Phonetics.key(joined)
                    // Exact spelling; same skeleton; one stray INSERTED
                    // consonant ("Sack abaclav"); or one DROPPED one
                    // ("ababov" lost the g) — both seen on-device
                    // 2026-07-22, always with letter similarity backing
                    // it up. The exact-domain anchor is what makes this
                    // much looser than general phonetic matching safe.
                    let similarity = Phonetics.similarity(joined, dictLocal)
                    let sounds: Bool
                    if joinedKey == dictKey {
                        sounds = similarity >= 0.5
                    } else if joinedKey.count <= dictKey.count + 1,
                              Phonetics.containsInOrder(dictKey, in: joinedKey) {
                        sounds = similarity >= 0.45
                    } else if joinedKey.count >= dictKey.count - 1,
                              Phonetics.containsInOrder(joinedKey, in: dictKey) {
                        sounds = similarity >= 0.5
                    } else {
                        sounds = false
                    }
                    if joined == dictLocal || sounds {
                        foldFrom = start
                        break
                    }
                }
                guard let foldFrom else {
                    // Lengths only, never content: enough to see the
                    // SHAPE of a miss from a remote debug.log.
                    let localKey = Phonetics.key(local.lowercased().filter(\.isLetter))
                    DebugLog.log("Email fold: site at dictionary domain, no name match (local \(local.count) chars/key \(localKey.count), dict key \(dictKey.count), \(words.count) word(s) before)")
                    continue
                }
                let kept = words[0..<foldFrom].joined(separator: " ")
                let replacement = kept.isEmpty ? cleanAddress : kept + " " + cleanAddress
                if ns.substring(with: match.range) != replacement {
                    DebugLog.log("Email fold: snapped (\(words.count - foldFrom) word(s) folded)")
                }
                result = ns.replacingCharacters(in: match.range, with: replacement)
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

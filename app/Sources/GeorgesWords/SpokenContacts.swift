import Foundation

/// Deterministic formatting of dictated phone numbers and email addresses.
///
/// Runs in Stage 1 (TranscriptCleaner) so it works with the LLM stage off —
/// and because light-polish mode is forbidden from rewording, the LLM would
/// never reformat these anyway. Everything here is conservative: it only
/// fires on shapes that are almost always a phone number or an address, so
/// ordinary prose is left untouched.
enum SpokenContacts {

    /// Parakeet v3 is multilingual and occasionally code-switches a
    /// spoken connector into another script — "dot" arrived as Cyrillic
    /// "дот" on-device (2026-07-22), which broke email assembly
    /// entirely. Normalize known alternate renderings back to English
    /// before any shape matching.
    private static let connectorTransliterations: [(pattern: String, replacement: String)] = [
        (#"(?i)\bдот\b"#, "dot"),
        (#"(?i)\bточка\b"#, "dot"),
        (#"(?i)\bпоинт\b"#, "point"),
    ]

    static func normalize(_ text: String) -> String {
        // Email first: it consumes the spoken word "at", which the phone
        // pass never touches, so order only matters for clarity.
        var result = text
        for entry in connectorTransliterations {
            result = result.replacingOccurrences(of: entry.pattern, with: entry.replacement, options: .regularExpression)
        }
        result = normalizeEmails(result)
        result = normalizePhones(result)
        return result
    }

    // MARK: - Email

    private static let digitWords: [String: Character] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3",
        "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
        "nine": "9",
    ]

    /// Common TLDs. Any two-letter country code is also accepted, so this only
    /// needs the multi-letter ones. Keeps "meet at noon dot the office" from
    /// being mistaken for an address.
    private static let knownTLDs: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "io", "co", "app",
        "dev", "ai", "gg", "tv", "fm", "info", "biz", "xyz", "tech", "online",
        "site", "club", "live", "news", "pro", "name", "mobi", "asia", "eu",
        "email", "cloud", "digital", "media", "studio", "design", "shop",
    ]

    /// First-domain-label words that are almost never a real domain — guards
    /// "look at this dot org" from turning into an address.
    private static let domainStopWords: Set<String> = [
        "this", "that", "these", "those", "the", "my", "your", "our", "his",
        "her", "their", "a", "an", "it",
    ]

    /// Domains that are overwhelmingly mail providers — "john at gmail
    /// dot com" is an address even with no other cue in the sentence.
    private static let mailProviders: Set<String> = [
        "gmail", "googlemail", "yahoo", "ymail", "hotmail", "outlook",
        "live", "msn", "icloud", "me", "mac", "proton", "protonmail",
        "pm", "aol", "fastmail", "hey", "zoho", "gmx", "mail",
        "sympatico", "rogers", "bell", "telus", "shaw", "videotron",
    ]

    /// Words that signal the speaker is dictating an address, BOUND to
    /// it: the cue must sit within three words of the candidate, on
    /// either side ("email me at john…", "jane at proton dot me is my
    /// address"). An unanchored search let a "send" much earlier in the
    /// sentence convert an unrelated "look at example dot com" (review
    /// follow-up, 2026-07-22).
    private static let emailCueWords = #"(?:e-?mail|mail|address|contact|reach|write|message|inbox|send)"#
    private static let leadingCuePattern = #"(?i)\b"# + emailCueWords + #"\b(?:\s+\S+){0,3}\s*$"#
    private static let trailingCuePattern = #"(?i)^\W*(?:\S+\s+){0,3}"# + emailCueWords + #"\b"#

    /// "john at gmail dot com" → "john@gmail.com";
    /// "jane dot doe at proton dot me" → "jane.doe@proton.me".
    static func normalizeEmails(_ text: String) -> String {
        // local = word (dot|dash|hyphen|underscore word)*   — the part before @
        // at    = the spoken word "at"
        // domain = word (dot|dash|hyphen|underscore word)+   — must connect,
        //          and (checked below) must contain at least one "dot".
        let connector = #"(?:dot|dash|hyphen|underscore|period)"#
        let local = #"([A-Za-z0-9]+(?:\s+"# + connector + #"\s+[A-Za-z0-9]+)*)"#
        let domain = #"([A-Za-z0-9]+(?:\s+"# + connector + #"\s+[A-Za-z0-9]+)+)"#
        let pattern = #"\b"# + local + #"\s+at\s+"# + domain + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let localRange = Range(match.range(at: 1), in: result),
                  let domainRange = Range(match.range(at: 2), in: result)
            else { continue }
            // Email-y wording bound to the match on either side ("email
            // me at…", "…is my address") licenses the conversion — but a
            // cue never reaches across a sentence boundary.
            let prefixStart = result.index(whole.lowerBound, offsetBy: -60, limitedBy: result.startIndex)
                ?? result.startIndex
            let suffixEnd = result.index(whole.upperBound, offsetBy: 60, limitedBy: result.endIndex)
                ?? result.endIndex
            var prefix = result[prefixStart..<whole.lowerBound]
            if let stop = prefix.lastIndex(where: { ".!?\n".contains($0) }) {
                prefix = prefix[prefix.index(after: stop)...]
            }
            var suffix = result[whole.upperBound..<suffixEnd]
            if let stop = suffix.firstIndex(where: { ".!?\n".contains($0) }) {
                suffix = suffix[..<stop]
            }
            // A dictation that IS the address — form entry, "john at
            // gmail dot com" and nothing else — needs no cue words:
            // the utterance's shape is the evidence (review follow-up,
            // 2026-07-22). Common-name locals convert here even though
            // they're in the word list.
            let outside = result[result.startIndex..<whole.lowerBound] + result[whole.upperBound...]
            let bareUtterance = outside.allSatisfy { $0.isWhitespace || $0.isPunctuation }
            let hasContext = bareUtterance
                || prefix.range(of: leadingCuePattern, options: .regularExpression) != nil
                || suffix.range(of: trailingCuePattern, options: .regularExpression) != nil
            guard let email = buildEmail(
                local: String(result[localRange]),
                domain: String(result[domainRange]),
                hasEmailContext: hasContext
            ) else { continue }
            result.replaceSubrange(whole, with: email)
        }
        return result
    }

    /// Assemble and validate an address, or nil if the domain doesn't look real.
    static func buildEmail(local rawLocal: String, domain rawDomain: String, hasEmailContext: Bool = false) -> String? {
        let localPart = collapse(rawLocal)
        let domainPart = collapse(rawDomain)

        guard !localPart.isEmpty,
              localPart.range(of: #"^[a-z0-9]+(?:[._-][a-z0-9]+)*$"#, options: .regularExpression) != nil
        else { return nil }

        let labels = domainPart.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard labels.count >= 2,
              let tld = labels.last,
              let first = labels.first,
              !domainStopWords.contains(first),
              isValidTLD(tld),
              labels.allSatisfy({ $0.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil })
        else { return nil }

        // "word at words dot tld" is also everyday prose ("look at
        // example dot com"). Convert only with a real email cue: a
        // multi-part local ("jane dot doe"), email-y wording bound to
        // it on either side, or a known mail provider — and the
        // provider only counts when the local part isn't itself an
        // ordinary word ("look at gmail dot com" is prose about a
        // website; "zachabugov at gmail dot com" is an address; "jane"
        // needs a cue because it's in the word list too) (review P2 +
        // follow-up).
        let multiPartLocal = localPart.contains(where: { "._-".contains($0) })
        let providerCue = mailProviders.contains(first) && !SystemWords.all.contains(localPart)
        guard multiPartLocal || providerCue || hasEmailContext else { return nil }

        return "\(localPart)@\(domainPart)"
    }

    private static func isValidTLD(_ tld: String) -> Bool {
        if tld.count == 2, tld.range(of: #"^[a-z]{2}$"#, options: .regularExpression) != nil { return true }
        return knownTLDs.contains(tld)
    }

    /// Lowercase and turn the spoken connectors into their symbols:
    /// "John dot Smith" → "john.smith", "gmail dot com" → "gmail.com".
    private static func collapse(_ phrase: String) -> String {
        var out = phrase.lowercased()
        out = out.replacingOccurrences(of: #"\s+(?:dot|period)\s+"#, with: ".", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+(?:dash|hyphen)\s+"#, with: "-", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\s+underscore\s+"#, with: "_", options: .regularExpression)
        return out.replacingOccurrences(of: " ", with: "")
    }

    // MARK: - Phone

    /// Format spoken and loosely-grouped phone numbers into a consistent shape:
    /// "five five five one two three four" → "555-1234",
    /// "eight zero zero five five five one two one two" → "(800) 555-1212",
    /// "call 800 555 1212" → "call (800) 555-1212".
    static func normalizePhones(_ text: String) -> String {
        var result = spelledDigitRuns(text)
        result = groupedDigitRuns(result)
        return result
    }

    /// A run of 7+ spoken digit words (with "double"/"triple" multipliers and
    /// "oh" for zero). Seven consecutive number words is essentially always a
    /// number being read aloud, so the false-positive risk is negligible.
    private static func spelledDigitRuns(_ text: String) -> String {
        let digit = #"(?:zero|oh|one|two|three|four|five|six|seven|eight|nine)"#
        let group = #"(?:(?:double|triple)[\s-]+)?"# + digit
        let pattern = #"\b("# + group + #"(?:[\s,–-]+"# + group + #")*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let digits = expandSpokenDigits(String(result[whole]))
            guard digits.count >= 7 else { continue }
            result.replaceSubrange(whole, with: formatPhone(digits) ?? digits)
        }
        return result
    }

    /// Walk the tokens of a matched run, applying "double"/"triple" to the
    /// following digit word: "double two" → "22".
    private static func expandSpokenDigits(_ run: String) -> String {
        let tokens = run.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .split(separator: " ")
            .map(String.init)

        var digits = ""
        var multiplier = 1
        for token in tokens {
            switch token {
            case "double": multiplier = 2
            case "triple": multiplier = 3
            default:
                guard let value = digitWords[token] else { multiplier = 1; continue }
                digits.append(String(repeating: value, count: multiplier))
                multiplier = 1
            }
        }
        return digits
    }

    /// Canonicalize digits the recognizer already grouped in a phone shape:
    /// "800 555 1212", "1-800-555-1212", "+1 800.555.1212" → "(800) 555-1212".
    /// Requires separators between groups, so a bare 10-digit id is left alone.
    private static func groupedDigitRuns(_ text: String) -> String {
        let pattern = #"(?<![\d(])(?:(\+?1)[\s.\-]?)?\(?(\d{3})\)?[\s.\-](\d{3})[\s.\-](\d{4})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let area = Range(match.range(at: 2), in: result),
                  let prefix = Range(match.range(at: 3), in: result),
                  let line = Range(match.range(at: 4), in: result)
            else { continue }
            let hasCountry = match.range(at: 1).location != NSNotFound
            let core = "(\(result[area])) \(result[prefix])-\(result[line])"
            result.replaceSubrange(whole, with: hasCountry ? "+1 \(core)" : core)
        }
        return result
    }

    /// 7 → "555-1234", 10 → "(800) 555-1212",
    /// 11 with a leading 1 → "+1 (800) 555-1212". Other lengths: nil.
    static func formatPhone(_ digits: String) -> String? {
        let d = Array(digits)
        switch d.count {
        case 7:
            return "\(String(d[0...2]))-\(String(d[3...6]))"
        case 10:
            return "(\(String(d[0...2]))) \(String(d[3...5]))-\(String(d[6...9]))"
        case 11 where d[0] == "1":
            return "+1 (\(String(d[1...3]))) \(String(d[4...6]))-\(String(d[7...10]))"
        default:
            return nil
        }
    }
}

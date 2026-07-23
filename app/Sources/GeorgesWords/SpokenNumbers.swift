import Foundation

/// Deterministic normalization of spelled-out numbers (backlog 2.4):
/// "twenty five percent" → "25%", "three thirty pm" → "3:30 PM".
/// Digit-adjacent forms ("50 percent") are handled in TranscriptCleaner;
/// this covers the spelled-out parsing, conservatively: only 0–99, and
/// times only when am/pm makes the intent unambiguous.
enum SpokenNumbers {

    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19
    ]

    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    /// "seven" / "twelve" / "twenty five" / "forty-two" → 0–99.
    static func value(of phrase: String) -> Int? {
        let words = phrase.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
        switch words.count {
        case 1:
            return units[words[0]] ?? tens[words[0]]
        case 2:
            guard let ten = tens[words[0]], let unit = units[words[1]], (1...9).contains(unit) else { return nil }
            return ten + unit
        default:
            return nil
        }
    }

    private static let onesPattern = #"(?:one|two|three|four|five|six|seven|eight|nine)"#
    private static let teensPattern = #"(?:ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen)"#
    private static let numberPattern =
        #"(?:(?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[ -](?:one|two|three|four|five|six|seven|eight|nine))?|"#
        + teensPattern + #"|"# + onesPattern + #"|zero)"#
    private static let hourPattern = #"(?:one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)"#
    private static let minutePattern =
        #"(?:oh[ -]"# + onesPattern + #"|(?:twenty|thirty|forty|fifty)(?:[ -]"# + onesPattern + #")?|"# + teensPattern + #")"#

    private static let scales: [String: Int] = [
        "hundred": 100, "thousand": 1_000, "million": 1_000_000,
        "billion": 1_000_000_000,
    ]

    static func normalize(_ text: String) -> String {
        var result = text
        // Years first (they carry no scale word, so the cardinal pass
        // can't see them), then cardinals, then DECIMALS BEFORE UNITS:
        // "…point seven dollars" must join into a decimal before the
        // unit pass can turn "seven dollars" into "$7" and strand
        // "point" (on-device, 2026-07-23).
        result = normalizeYears(result)
        result = normalizeCardinals(result)
        result = normalizeDecimals(result)
        result = normalizeUnits(result)
        result = normalizeTimes(result)
        return result
    }

    /// "twenty twenty-six" → 2026, "nineteen eighty-four" → 1984,
    /// "twenty oh nine" → 2009 (owner report, 2026-07-23). Only
    /// century + two-digit pairs — "twenty-five people" has no
    /// second pair-word and stays as spoken.
    private static func normalizeYears(_ text: String) -> String {
        let century = #"(nineteen|twenty)"#
        let rest = #"((?:twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety)(?:[ -](?:one|two|three|four|five|six|seven|eight|nine))?|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|oh[ -](?:one|two|three|four|five|six|seven|eight|nine))"#
        let pattern = #"\b"# + century + #"[ -]"# + rest + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let centuryRange = Range(match.range(at: 1), in: result),
                  let restRange = Range(match.range(at: 2), in: result)
            else { continue }
            let centuryValue = result[centuryRange].lowercased() == "nineteen" ? 19 : 20
            let restPhrase = result[restRange].lowercased().replacingOccurrences(of: "-", with: " ")
            let restValue: Int?
            if restPhrase.hasPrefix("oh ") {
                restValue = value(of: String(restPhrase.dropFirst(3)))
            } else {
                restValue = value(of: restPhrase)
            }
            guard let restValue else { continue }
            result.replaceSubrange(whole, with: "\(centuryValue)" + String(format: "%02d", restValue))
        }
        return result
    }

    private static let smallDigitWord = #"(?:zero|oh|one|two|three|four|five|six|seven|eight|nine)"#

    /// Spoken decimals, both sides possibly still words: "twelve point
    /// five" → 12.5, "2,756,243 point seven" → 2,756,243.7, "point
    /// seven five" → .75 digits. Prose is protected by requiring a real
    /// number before "point" — "make a point three times" stays words.
    private static func normalizeDecimals(_ text: String) -> String {
        let integer = #"((?:\d{1,3}(?:,\d{3})+|\d+)|"# + numberPattern + #")"#
        let fraction = #"(\d+|"# + smallDigitWord + #"(?:[ -]"# + smallDigitWord + #")*)"#
        let pattern = #"\b"# + integer + #"\s+point\s+"# + fraction + #"\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let integerRange = Range(match.range(at: 1), in: result),
                  let fractionRange = Range(match.range(at: 2), in: result)
            else { continue }

            let integerText = String(result[integerRange])
            let integerPart: String
            if integerText.first?.isNumber == true {
                integerPart = integerText
            } else if let parsed = value(of: integerText) {
                integerPart = String(parsed)
            } else {
                continue
            }

            let fractionText = result[fractionRange].lowercased()
            let fractionPart: String
            if fractionText.first?.isNumber == true {
                fractionPart = String(fractionText)
            } else {
                let tokens = fractionText.replacingOccurrences(of: "-", with: " ")
                    .split(separator: " ").map(String.init)
                let digits = tokens.compactMap { token -> String? in
                    if token == "oh" { return "0" }
                    guard let digit = units[token], digit <= 9 else { return nil }
                    return String(digit)
                }
                guard digits.count == tokens.count else { continue }
                fractionPart = digits.joined()
            }
            result.replaceSubrange(whole, with: integerPart + "." + fractionPart)
        }
        return result
    }

    /// 2756000 → "2,756,000". Only magnitude-derived cardinals are ever
    /// grouped — a spoken "million"/"thousand" is always a quantity,
    /// never a zip code or an ID.
    private static func grouped(_ value: Int) -> String {
        var out: [Character] = []
        for (index, digit) in String(value).reversed().enumerated() {
            if index > 0 && index % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return String(out.reversed())
    }

    /// Parse a full spelled-out cardinal ("one thousand two hundred and five")
    /// into its integer value, or nil if any token isn't a number word.
    static func cardinalValue(of phrase: String) -> Int? {
        let words = phrase.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { $0 != "and" }
        guard !words.isEmpty else { return nil }

        var total = 0
        var current = 0
        for word in words {
            if let unit = units[word] {
                current += unit
            } else if let ten = tens[word] {
                current += ten
            } else if word == "hundred" {
                current = max(current, 1) * 100
            } else if let scale = scales[word], scale >= 1_000 {
                total += max(current, 1) * scale
                current = 0
            } else {
                return nil
            }
        }
        return total + current
    }

    private static let cardinalWord =
        #"(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|"#
        + #"thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|"#
        + #"twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|"#
        + #"hundred|thousand|million|billion)"#

    /// Convert spelled-out numbers that carry a magnitude word to digits:
    /// "one hundred twenty three" → "123", "two thousand" → "2000".
    /// Deliberately conservative — a phrase is only converted when it contains
    /// BOTH a scale word (hundred/thousand/…) and an ordinary number word, so
    /// small prose counts ("three ideas") and idioms ("thanks a million") are
    /// left as spoken.
    private static func normalizeCardinals(_ text: String) -> String {
        let pattern = #"\b("# + cardinalWord + #"(?:[\s-]+(?:and[\s-]+)?"# + cardinalWord + #")*)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result) else { continue }
            let phrase = String(result[whole]).lowercased()
            let tokens = Set(phrase.replacingOccurrences(of: "-", with: " ").split(separator: " ").map(String.init))
            let hasScale = tokens.contains { scales[$0] != nil }
            let hasPlainNumber = tokens.contains { units[$0] != nil || tens[$0] != nil }
            guard hasScale, hasPlainNumber, let value = cardinalValue(of: phrase) else { continue }
            result.replaceSubrange(whole, with: value >= 10_000 ? grouped(value) : String(value))
        }
        return result
    }

    /// "<spelled number> percent|dollars|degrees" → "N%", "$N", "N°".
    private static func normalizeUnits(_ text: String) -> String {
        let pattern = #"\b("# + numberPattern + #")\s+(percent|dollars|degrees)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        // Replace back-to-front so earlier match ranges stay valid.
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let numberRange = Range(match.range(at: 1), in: result),
                  let unitRange = Range(match.range(at: 2), in: result),
                  let number = value(of: String(result[numberRange]))
            else { continue }
            let replacement: String
            switch result[unitRange].lowercased() {
            case "percent": replacement = "\(number)%"
            case "dollars": replacement = "$\(number)"
            case "degrees": replacement = "\(number)°"
            default: continue
            }
            result.replaceSubrange(whole, with: replacement)
        }
        return result
    }

    /// "three thirty pm" → "3:30 PM"; "seven pm" → "7 PM"; "nine oh five am"
    /// → "9:05 AM". Requires am/pm — a bare "five thirty" stays as spoken.
    private static func normalizeTimes(_ text: String) -> String {
        let pattern = #"\b("# + hourPattern + #")(?:\s+("# + minutePattern + #"))?\s+([ap])(?:\.\s?|\s)?m\b\.?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let hourRange = Range(match.range(at: 1), in: result),
                  let apRange = Range(match.range(at: 3), in: result),
                  let hour = value(of: String(result[hourRange]))
            else { continue }

            var minuteText = ""
            if match.range(at: 2).location != NSNotFound, let minuteRange = Range(match.range(at: 2), in: result) {
                let phrase = result[minuteRange].lowercased().replacingOccurrences(of: "-", with: " ")
                let minute: Int?
                if phrase.hasPrefix("oh ") {
                    minute = value(of: String(phrase.dropFirst(3)))
                } else {
                    minute = value(of: phrase)
                }
                guard let minute else { continue }
                minuteText = String(format: ":%02d", minute)
            }

            let suffix = result[apRange].lowercased() == "p" ? "PM" : "AM"
            result.replaceSubrange(whole, with: "\(hour)\(minuteText) \(suffix)")
        }
        return result
    }
}

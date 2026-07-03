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

    static func normalize(_ text: String) -> String {
        var result = text
        result = normalizeUnits(result)
        result = normalizeTimes(result)
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

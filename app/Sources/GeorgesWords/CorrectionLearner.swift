import AppKit
import ApplicationServices

// The auto-learning dictionary (ADR 0005). Three pieces:
//
//   FocusedFieldReader — re-read the focused text field a few seconds
//   after an insertion, via the same AX API the inserter uses.
//
//   CorrectionDetector — word-align what we inserted against what the
//   field says now; replaced word runs that still *resemble* the original
//   are treated as the user fixing a mishearing.
//
//   CorrectionStore — the local suggestion queue surfaced in the
//   Dictionary tab; accepting one appends a "heard -> Correct" line to
//   the personal dictionary. Nothing is ever added automatically.

/// Reads the full value of the currently focused text field.
enum FocusedFieldReader {

    static func read() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
            let focusedRef,
            CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }

        let element = focusedRef as! AXUIElement
        var valueRef: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &valueRef
        ) == .success else { return nil }
        return valueRef as? String
    }
}

/// Extracts word-level substitutions between an inserted transcript and
/// the text as the user has since edited it.
enum CorrectionDetector {

    struct Substitution: Equatable {
        let heard: String
        let corrected: String
    }

    private struct Token {
        let original: String
        let normalized: String
    }

    /// Words whose replacement is a wording choice, not a mishearing fix.
    private static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "to", "of", "in", "on", "at",
        "for", "with", "is", "are", "was", "were", "be", "been", "it", "its",
        "that", "this", "these", "those", "i", "you", "we", "they", "he",
        "she", "my", "your", "our", "their", "his", "her", "me", "us", "them",
        "do", "does", "did", "not", "no", "yes", "so", "just", "very",
        "really", "have", "has", "had", "will", "would", "can", "could",
        "should", "as", "if", "then", "than", "there", "here", "what", "when",
        "where", "who", "how", "why", "all", "some", "any", "up", "down",
        "out", "about", "into", "over", "after", "before", "again", "more",
        "most", "other", "get", "got", "go", "going", "like", "one", "two"
    ]

    /// Compare the inserted transcript against the field's current text and
    /// return plausible mishearing fixes. Returns [] when the field no
    /// longer resembles what was inserted (user rewrote or moved on).
    static func substitutions(from inserted: String, to fieldText: String) -> [Substitution] {
        var a = tokenize(inserted)
        var b = tokenize(fieldText)
        guard !a.isEmpty, !b.isEmpty else { return [] }

        // Bound the O(n·m) alignment. Dictations are short; huge fields
        // (long documents) keep only the tail, where insertions usually are.
        if a.count > 400 { a = Array(a.prefix(400)) }
        if b.count > 2000 { b = Array(b.suffix(2000)) }

        let n = a.count
        let m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i].normalized == b[j].normalized
                    ? dp[i + 1][j + 1] + 1
                    : max(dp[i + 1][j], dp[i][j + 1])
            }
        }

        // If well under 60% of the inserted words survive, we're not
        // looking at a lightly-corrected version of our text — learn nothing.
        guard dp[0][0] * 10 >= n * 6 else { return [] }

        // Walk the alignment; between matches, a run of deleted words next
        // to a run of inserted words is a candidate substitution.
        var results: [Substitution] = []
        var pendingHeard: [Token] = []
        var pendingCorrected: [Token] = []

        func flush() {
            defer {
                pendingHeard = []
                pendingCorrected = []
            }
            guard (1...3).contains(pendingHeard.count), (1...3).contains(pendingCorrected.count) else { return }
            let heard = pendingHeard.map(\.original).joined(separator: " ")
            let corrected = pendingCorrected.map(\.original).joined(separator: " ")
            guard heard.lowercased() != corrected.lowercased() else { return }
            // Every replacement word being a common word = a wording edit.
            guard !pendingCorrected.allSatisfy({ stopwords.contains($0.normalized) }) else { return }
            guard corrected.contains(where: { $0.isLetter }) else { return }
            // Mishearings resemble the correction; full rewrites don't.
            let similarity = Self.similarity(
                pendingHeard.map(\.normalized).joined(),
                pendingCorrected.map(\.normalized).joined()
            )
            guard similarity >= 0.35 else { return }
            results.append(Substitution(heard: heard, corrected: corrected))
        }

        var i = 0
        var j = 0
        while i < n && j < m {
            if a[i].normalized == b[j].normalized {
                flush()
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                pendingHeard.append(a[i])
                i += 1
            } else {
                pendingCorrected.append(b[j])
                j += 1
            }
        }
        while i < n {
            pendingHeard.append(a[i])
            i += 1
        }
        // Trailing field text isn't "inserted words" — the user may simply
        // have kept typing. Only flush if a heard-run is pending too.
        if !pendingHeard.isEmpty && pendingCorrected.isEmpty {
            pendingHeard = []
        }
        flush()

        return results
    }

    private static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).compactMap { raw in
            let stripped = String(raw).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !stripped.isEmpty else { return nil }
            return Token(original: stripped, normalized: stripped.lowercased())
        }
    }

    /// Normalized Levenshtein similarity in 0…1.
    private static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.unicodeScalars)
        let y = Array(b.unicodeScalars)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var prev = Array(0...y.count)
        var curr = Array(repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            curr[0] = i
            for j in 1...y.count {
                curr[j] = Swift.min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)
                )
            }
            swap(&prev, &curr)
        }
        let distance = Double(prev[y.count])
        return 1 - distance / Double(max(x.count, y.count))
    }
}

/// The suggestion queue: correction candidates observed locally, waiting
/// for a one-click accept (never auto-added). Persisted in Application
/// Support next to the history; dismissed pairs are remembered so they
/// don't come back.
final class CorrectionStore: ObservableObject {

    static let shared = CorrectionStore()
    private static let maxSuggestions = 50
    private static let maxDismissed = 300

    struct Suggestion: Codable, Identifiable, Equatable {
        let id: UUID
        var heard: String
        var corrected: String
        var timesSeen: Int
        var lastSeen: Date
    }

    private struct Saved: Codable {
        var suggestions: [Suggestion]
        var dismissed: [String]
    }

    @Published private(set) var suggestions: [Suggestion] = []
    private var dismissed: [String] = []
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeorgesWords", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("corrections.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            suggestions = saved.suggestions
            dismissed = saved.dismissed
        }
    }

    private static func key(_ heard: String, _ corrected: String) -> String {
        heard.lowercased() + "\u{1F}" + corrected.lowercased()
    }

    func add(heard: String, corrected: String, settings: AppSettings) {
        let key = Self.key(heard, corrected)
        guard !dismissed.contains(key) else { return }
        // Already fixed by an existing dictionary mapping — nothing to learn.
        let heardLower = heard.lowercased()
        guard !settings.dictionaryReplacements.contains(where: { $0.heard.lowercased() == heardLower }) else { return }

        if let index = suggestions.firstIndex(where: { Self.key($0.heard, $0.corrected) == key }) {
            suggestions[index].timesSeen += 1
            suggestions[index].lastSeen = Date()
        } else {
            suggestions.insert(
                Suggestion(id: UUID(), heard: heard, corrected: corrected, timesSeen: 1, lastSeen: Date()),
                at: 0
            )
            if suggestions.count > Self.maxSuggestions {
                suggestions.removeLast(suggestions.count - Self.maxSuggestions)
            }
        }
        save()
    }

    /// One click: the pair becomes a "heard -> Correct" dictionary line.
    func accept(_ suggestion: Suggestion, into settings: AppSettings) {
        var text = settings.dictionaryText
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "\(suggestion.heard) -> \(suggestion.corrected)"
        settings.dictionaryText = text
        suggestions.removeAll { $0.id == suggestion.id }
        save()
    }

    func dismiss(_ suggestion: Suggestion) {
        dismissed.append(Self.key(suggestion.heard, suggestion.corrected))
        if dismissed.count > Self.maxDismissed {
            dismissed.removeFirst(dismissed.count - Self.maxDismissed)
        }
        suggestions.removeAll { $0.id == suggestion.id }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(suggestions: suggestions, dismissed: dismissed)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

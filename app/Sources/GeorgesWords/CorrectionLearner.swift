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
        guard let element = AXFocus.focusedElement(logContext: "Correction re-read") else { return nil }
        return read(element: element)
    }

    /// Reads a specific element — used when the inserter remembered exactly
    /// which field it wrote into, so the re-read can follow the field itself
    /// instead of trusting whatever happens to have focus later.
    static func read(element: AXUIElement) -> String? {
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
    ///
    /// The comparison anchors to the LATEST place the inserted text
    /// plausibly starts: a field that already holds an older, unedited
    /// copy of the same sentence (repeated dictations!) would otherwise
    /// outscore the copy the user just fixed — the diff bound to the old
    /// copy and the fix became invisible (QA finding, 2026-07-22). Only
    /// when no anchored window resembles the insertion is the whole
    /// field diffed as before.
    static func substitutions(from inserted: String, to fieldText: String) -> [Substitution] {
        var a = tokenize(inserted)
        var b = tokenize(fieldText)
        guard !a.isEmpty, !b.isEmpty else { return [] }

        // Bound the O(n·m) alignment. Dictations are short; huge fields
        // (long documents) keep only the tail, where insertions usually are.
        if a.count > 400 { a = Array(a.prefix(400)) }
        if b.count > 2000 { b = Array(b.suffix(2000)) }

        // Room for the (possibly edited) copy plus a little typing after
        // it — but never enough to swallow a whole earlier copy as well.
        let windowLength = a.count + max(8, a.count / 2)
        // Anchor on the first inserted word; if the user edited that very
        // word, the second word serves. Latest occurrences first.
        for anchorOffset in 0..<min(2, a.count) {
            let anchor = a[anchorOffset].normalized
            var positions: [Int] = []
            for (index, token) in b.enumerated() where token.normalized == anchor {
                positions.append(index)
            }
            for position in positions.suffix(3).reversed() {
                let start = max(0, position - anchorOffset)
                let window = Array(b[start..<min(b.count, start + windowLength)])
                if let found = align(a, window, anchored: true) { return found }
            }
        }
        return align(a, b, anchored: false) ?? []
    }

    /// One aligned comparison. Returns nil when this window doesn't
    /// resemble the insertion — the caller then tries the next anchor,
    /// or the whole field as the last resort.
    private static func align(_ a: [Token], _ b: [Token], anchored: Bool) -> [Substitution]? {
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

        // If well under 60% of the inserted words survive, we're usually
        // not looking at a lightly-corrected version of our text. Short
        // dictations are the exception: fixing two words out of four is a
        // "heavy rewrite" by percentage but exactly what a mishearing fix
        // looks like. Those run in strict mode — a single candidate at a
        // higher similarity bar — instead of learning nothing (backlog 2.5).
        let survivalOK = dp[0][0] * 10 >= n * 6
        let strict = !survivalOK
        if anchored {
            // An anchored window must genuinely resemble the insertion;
            // the strict small-dictation rescue belongs to the whole-field
            // fallback only, or a garbage window at some stray anchor
            // would end the anchor search early.
            guard survivalOK else { return nil }
        } else {
            guard survivalOK || n <= 12 else { return nil }
        }

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
            let similarity = Phonetics.similarity(
                pendingHeard.map(\.normalized).joined(),
                pendingCorrected.map(\.normalized).joined()
            )
            if strict {
                // Low word survival: only a strongly-resembling single fix
                // is trusted (the exactly-one rule is enforced after the walk).
                guard similarity >= 0.55 else { return }
            } else if similarity < 0.35 {
                // Sound-alike fixes spelled differently ("quay" → "key")
                // can fail the letter distance — give phonetics a second
                // vote. Suggestions still need a human click, so a looser
                // gate here costs a dismissal, never a bad auto-entry.
                let phonetic = Phonetics.similarity(
                    pendingHeard.map { Phonetics.key($0.normalized) }.joined(),
                    pendingCorrected.map { Phonetics.key($0.normalized) }.joined()
                )
                guard phonetic >= 0.5 else { return }
            }
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
        // Trailing field text pairs with a trailing deleted run — the user
        // replaced the final words (previously undetectable). With nothing
        // deleted it's just the user typing onward, never a correction.
        // A long trailing run (deleted a word, then kept writing) fails
        // the 1–3 word filter in flush(), so it can't learn garbage.
        if !pendingHeard.isEmpty {
            while j < m {
                pendingCorrected.append(b[j])
                j += 1
            }
        }
        if !pendingHeard.isEmpty && pendingCorrected.isEmpty {
            pendingHeard = []
        }
        flush()

        // Strict mode trusts exactly one strong fix; several "fixes" in a
        // barely-surviving text is a rewrite wearing a costume.
        if strict && results.count != 1 { return [] }
        return results
    }


    private static func tokenize(_ text: String) -> [Token] {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).compactMap { raw in
            let stripped = String(raw).trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            guard !stripped.isEmpty else { return nil }
            return Token(original: stripped, normalized: stripped.lowercased())
        }
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
        // Optional: absent in files written before the badge existed.
        var unreviewed: Int?
    }

    @Published private(set) var suggestions: [Suggestion] = []
    /// Suggestions captured since the Dictionary tab was last opened —
    /// drives the sidebar badge so captures aren't silent (backlog 2.5).
    @Published private(set) var unreviewedCount = 0
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
            unreviewedCount = min(saved.unreviewed ?? 0, saved.suggestions.count)
        }
    }

    private static func key(_ heard: String, _ corrected: String) -> String {
        heard.lowercased() + "\u{1F}" + corrected.lowercased()
    }

    /// Returns true when a brand-new suggestion was queued (as opposed to a
    /// repeat sighting, a dismissed pair, or an already-mapped word) — the
    /// caller uses that to decide whether the capture is worth announcing.
    @discardableResult
    func add(heard: String, corrected: String, settings: AppSettings) -> Bool {
        let key = Self.key(heard, corrected)
        guard !dismissed.contains(key) else { return false }
        // Already fixed by an existing dictionary mapping — nothing to learn.
        let heardLower = heard.lowercased()
        guard !settings.dictionaryReplacements.contains(where: { $0.heard.lowercased() == heardLower }) else { return false }

        var isNew = false
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
            unreviewedCount += 1
            isNew = true
        }
        save()
        return isNew
    }

    /// The Dictionary tab was opened — everything in it has been seen.
    func markReviewed() {
        guard unreviewedCount != 0 else { return }
        unreviewedCount = 0
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
        let saved = Saved(suggestions: suggestions, dismissed: dismissed, unreviewed: unreviewedCount)
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

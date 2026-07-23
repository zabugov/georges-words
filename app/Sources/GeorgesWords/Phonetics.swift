import Foundation

/// Shared sound-alike matching, used by the correction learner (ADR 0005
/// amendment) and the dictionary's phonetic pass (TranscriptCleaner,
/// 2026-07-22): the ASR invents a NEW misspelling of an unknown name
/// every time it hears it, so exact-string matching can never keep up —
/// only matching by sound can.
enum Phonetics {

    /// Reduce a word to a rough consonant skeleton so sound-alike
    /// spellings compare close ("quay" → "kw", "key" → "k"; "abagoff"
    /// and "abugov" both → "apkf"). Deliberately crude — every caller
    /// pairs it with a letter-similarity check or a human click.
    /// Expects lowercase input.
    static func key(_ word: String) -> String {
        var text = word.filter(\.isLetter)
        // Silent/aliased clusters first, while their context is intact.
        for (from, to) in [
            ("kn", "n"), ("gn", "n"), ("pn", "n"), ("wr", "r"),
            ("wh", "w"), ("qu", "kw"), ("ph", "f"), ("ck", "k")
        ] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        var skeleton = ""
        for (offset, ch) in text.enumerated() {
            let mapped: Character
            switch ch {
            case "a", "e", "i", "o", "u", "y", "h":
                // Vowels (and near-silent h) vary freely between a
                // mishearing and its fix — keep one only word-initially.
                if offset == 0 { mapped = ch } else { continue }
            // Voiced/unvoiced pairs fold together — g/k, b/p, d/t, v/f,
            // z/s, j/g are exactly what mishearings swap ("Abakoff" vs
            // "Abugov").
            case "c", "q", "g", "j": mapped = "k"
            case "z": mapped = "s"
            case "d": mapped = "t"
            case "b": mapped = "p"
            case "v": mapped = "f"
            default: mapped = ch
            }
            if skeleton.last != mapped { skeleton.append(mapped) }
        }
        return skeleton
    }

    /// Fold Cyrillic/Greek lookalike letters to their Latin twins. The
    /// multilingual recognizer code-switches mid-word ("дот" for "dot"),
    /// and a dictionary line dictated or pasted through it can carry
    /// invisible homoglyphs — "zаchabugov" with a Cyrillic а LOOKS
    /// identical but matches nothing (on-device, 2026-07-23). Applied to
    /// both sides of every comparison, and to replacements so a poisoned
    /// stored spelling can't propagate. Accented Latin (é, ü) is left
    /// alone — only cross-script lookalikes fold.
    static func latinize(_ text: String) -> String {
        let map: [Character: Character] = [
            "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y",
            "х": "x", "і": "i", "ј": "j", "ѕ": "s", "к": "k", "м": "m",
            "т": "t", "в": "b", "н": "h", "д": "d", "г": "g", "б": "b",
            "п": "p", "ф": "f", "л": "l", "з": "z", "ш": "s", "и": "i",
            "α": "a", "ο": "o", "ν": "v", "ι": "i", "κ": "k", "τ": "t",
            "ρ": "p", "ε": "e", "υ": "u",
        ]
        guard text.contains(where: { map[$0] != nil }) else { return text }
        return String(text.map { map[$0] ?? $0 })
    }

    /// True when `needle`'s characters all appear in `haystack` in order
    /// (subsequence). Used to tell an INSERTED stray consonant (clipped
    /// audio: "aprkf" still contains all of "apkf") from a MISSING one
    /// ("apf" lacks the k — a genuinely different word).
    static func containsInOrder(_ needle: String, in haystack: String) -> Bool {
        var iterator = haystack.makeIterator()
        outer: for target in needle {
            while let ch = iterator.next() {
                if ch == target { continue outer }
            }
            return false
        }
        return true
    }

    /// Normalized Levenshtein similarity in 0…1.
    static func similarity(_ a: String, _ b: String) -> Double {
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

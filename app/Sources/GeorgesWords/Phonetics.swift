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

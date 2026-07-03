import Foundation

/// Local-only usage counters — never leave the device.
enum StatsStore {

    private static let wordsKey = "Stats.totalWords"
    private static let dictationsKey = "Stats.totalDictations"

    static func record(words: Int) {
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: wordsKey) + words, forKey: wordsKey)
        defaults.set(defaults.integer(forKey: dictationsKey) + 1, forKey: dictationsKey)
    }

    /// e.g. "3,412 words dictated · ~1.1 h saved"
    static var summary: String {
        let defaults = UserDefaults.standard
        let words = defaults.integer(forKey: wordsKey)
        guard words > 0 else { return "No dictations yet" }

        // Speaking ≈ 150 wpm vs typing ≈ 45 wpm.
        let savedMinutes = Double(words) * (1.0 / 45.0 - 1.0 / 150.0)
        let savedText: String
        if savedMinutes >= 90 {
            savedText = String(format: "~%.1f h saved", savedMinutes / 60)
        } else {
            savedText = "~\(Int(savedMinutes.rounded())) min saved"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let wordsText = formatter.string(from: NSNumber(value: words)) ?? "\(words)"
        return "\(wordsText) words dictated · \(savedText)"
    }
}

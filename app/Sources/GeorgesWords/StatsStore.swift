import Foundation

/// Local-only usage counters — never leave the device.
final class StatsStore: ObservableObject {

    static let shared = StatsStore()

    private static let wordsKey = "Stats.totalWords"
    private static let dictationsKey = "Stats.totalDictations"

    @Published private(set) var totalWords: Int
    @Published private(set) var totalDictations: Int

    private init() {
        let defaults = UserDefaults.standard
        totalWords = defaults.integer(forKey: Self.wordsKey)
        totalDictations = defaults.integer(forKey: Self.dictationsKey)
    }

    func record(words: Int) {
        totalWords += words
        totalDictations += 1
        let defaults = UserDefaults.standard
        defaults.set(totalWords, forKey: Self.wordsKey)
        defaults.set(totalDictations, forKey: Self.dictationsKey)
    }

    /// Speaking ≈ 150 wpm vs typing ≈ 45 wpm.
    var minutesSaved: Double {
        Double(totalWords) * (1.0 / 45.0 - 1.0 / 150.0)
    }

    var timeSavedText: String {
        if minutesSaved >= 90 {
            return String(format: "%.1f h", minutesSaved / 60)
        }
        return "\(Int(minutesSaved.rounded())) min"
    }

    /// e.g. "3,412 words dictated · ~1.1 h saved"
    var summary: String {
        guard totalWords > 0 else { return "No dictations yet" }
        return "\(Self.formatted(totalWords)) words dictated · ~\(timeSavedText) saved"
    }

    static func formatted(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

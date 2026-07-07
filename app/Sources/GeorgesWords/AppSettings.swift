import AppKit
import Combine
import ServiceManagement

/// Which on-device speech-to-text engine transcribes the audio.
enum SpeechEngine: String, CaseIterable, Identifiable {
    case parakeet
    case whisper

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeet: return "Parakeet v3 — fastest (recommended)"
        case .whisper: return "Whisper (WhisperKit)"
        }
    }

    /// Whether Parakeet was compiled into this build (GW_PARAKEET=1).
    static var parakeetAvailable: Bool {
        #if PARAKEET
        return true
        #else
        return false
        #endif
    }

    /// Engines selectable in this build.
    static var available: [SpeechEngine] {
        parakeetAvailable ? allCases : [.whisper]
    }
}

/// How aggressively the LLM polish pass may edit.
enum PolishStrength: String, CaseIterable, Identifiable {
    case light
    case full

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "Keep my words — fillers & punctuation only"
        case .full: return "Rewrite for clarity"
        }
    }
}

/// A user style note attached to one app: "in Obsidian, use markdown
/// headings". Matched against the frontmost app's bundle identifier.
struct AppInstruction: Codable, Identifiable, Equatable {
    var id = UUID()
    var appName: String
    var bundleID: String
    var instruction: String
}

/// User preferences, persisted to UserDefaults, observable from SwiftUI.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// Speech-to-text engine (Parakeet via FluidAudio, or Whisper via WhisperKit).
    @Published var engine: SpeechEngine {
        didSet { defaults.set(engine.rawValue, forKey: "Engine") }
    }

    /// WhisperKit model identifier (prefix-matched against argmaxinc/whisperkit-coreml).
    /// Only used when `engine == .whisper`.
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: "ModelName") }
    }

    @Published var hotkey: HotkeySpec {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) {
                defaults.set(data, forKey: "HotkeySpec")
            }
        }
    }

    /// How long dictation history is kept (backlog 8.2).
    @Published var historyRetention: HistoryRetention {
        didSet {
            defaults.set(historyRetention.rawValue, forKey: "HistoryRetention")
            HistoryStore.shared.apply(historyRetention)
        }
    }

    /// Backlog 8.3: the one switch that stops the app watching
    /// post-dictation edits for learnable corrections (ADR 0005). The
    /// manual "Fix the last transcript" flow stays available — that one
    /// is explicit, not watching.
    @Published var correctionLearningEnabled: Bool {
        didSet { defaults.set(correctionLearningEnabled, forKey: "CorrectionLearningEnabled") }
    }

    /// Personal style samples by tone profile (backlog 3.3): the user's
    /// own writing, pasted in Settings, that full polish should imitate.
    /// Keyed by ToneProfile rawValue; empty strings mean "no sample".
    @Published var styleSamples: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(styleSamples) {
                defaults.set(data, forKey: "StyleSamples")
            }
        }
    }

    /// The sample the polish prompt should imitate for this tone, trimmed
    /// and bounded — long pastes would slow every polish call.
    func styleSample(for tone: ToneProfile) -> String? {
        let sample = (styleSamples[tone.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        return String(sample.prefix(700))
    }

    /// Second hotkey: hold it and say how to change the last dictation
    /// (command mode, backlog 4.4). Nil = off until the user picks a key.
    @Published var commandHotkey: HotkeySpec? {
        didSet {
            if let commandHotkey, let data = try? JSONEncoder().encode(commandHotkey) {
                defaults.set(data, forKey: "CommandHotkeySpec")
            } else {
                defaults.removeObject(forKey: "CommandHotkeySpec")
            }
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Stage-2 formatting: rewrite transcripts with a local LLM via Ollama.
    @Published var llmEnabled: Bool {
        didSet { defaults.set(llmEnabled, forKey: "LLMEnabled") }
    }

    /// Light = preserve the speaker's exact wording; Full = restructure.
    @Published var polishStrength: PolishStrength {
        didSet { defaults.set(polishStrength.rawValue, forKey: "PolishStrength") }
    }


    // The settled configuration (2026-07-05): light polish is fast and
    // good at 1.5b, and it keeps the onboarding "about 1 GB" promise true.
    static let defaultLLMModel = "qwen2.5:1.5b"

    /// Ollama model tag used for the polish pass. May be empty or
    /// mid-edit in the Settings field — use `effectiveLLMModel` when
    /// actually calling Ollama.
    @Published var llmModel: String {
        didSet { defaults.set(llmModel, forKey: "LLMModel") }
    }

    /// The model tag to actually use: falls back to the default when the
    /// Settings field is emptied, so polish never silently stops working.
    var effectiveLLMModel: String {
        let trimmed = llmModel.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? Self.defaultLLMModel : trimmed
    }

    /// Personal dictionary, one entry per line. A plain line enforces that
    /// term's exact spelling; a "heard -> Correct" line rewrites a specific
    /// mishearing (the auto-learning dictionary emits these — ADR 0005).
    @Published var dictionaryText: String {
        didSet { defaults.set(dictionaryText, forKey: "Dictionary") }
    }

    /// Spellings to enforce: plain lines, plus the correct side of every
    /// mapping (so the LLM pass also knows these words).
    var dictionaryTerms: [String] {
        dictionaryText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                Self.parseReplacement(line)?.correct ?? line
            }
    }

    /// The "heard -> Correct" mappings, applied in the rule-based pass.
    var dictionaryReplacements: [(heard: String, correct: String)] {
        dictionaryText
            .split(separator: "\n")
            .compactMap { Self.parseReplacement(String($0)) }
    }

    private static func parseReplacement(_ line: String) -> (heard: String, correct: String)? {
        for arrow in ["->", "→"] {
            guard let range = line.range(of: arrow) else { continue }
            let heard = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let correct = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !heard.isEmpty, !correct.isEmpty else { return nil }
            return (heard, correct)
        }
        return nil
    }

    /// Show a live partial transcript in the pill while speaking.
    @Published var previewEnabled: Bool {
        didSet { defaults.set(previewEnabled, forKey: "PreviewEnabled") }
    }

    /// Play a sound when recording starts and stops.
    @Published var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: "SoundsEnabled") }
    }

    /// Voice shortcuts: say the trigger, get the expansion.
    @Published var snippets: [Snippet] {
        didSet {
            if let data = try? JSONEncoder().encode(snippets) {
                defaults.set(data, forKey: "Snippets")
            }
        }
    }

    /// Per-app style notes, applied on top of the built-in tone profile
    /// in full-rewrite polish (backlog 3.2).
    @Published var appInstructions: [AppInstruction] {
        didSet {
            if let data = try? JSONEncoder().encode(appInstructions) {
                defaults.set(data, forKey: "AppInstructions")
            }
        }
    }

    /// The style note matching a frontmost-app bundle ID, if any.
    func appInstruction(for bundleID: String) -> String? {
        Self.matchInstruction(appInstructions, bundleID: bundleID)
    }

    static func matchInstruction(_ instructions: [AppInstruction], bundleID: String) -> String? {
        guard !bundleID.isEmpty else { return nil }
        for entry in instructions {
            let key = entry.bundleID.trimmingCharacters(in: .whitespaces).lowercased()
            let note = entry.instruction.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !note.isEmpty else { continue }
            if bundleID.lowercased().contains(key) { return note }
        }
        return nil
    }

    static let modelOptions: [(name: String, label: String)] = [
        ("base.en", "base.en — fastest, rough accuracy (~150 MB)"),
        ("small.en", "small.en — good balance (default, ~500 MB)"),
        ("distil-large-v3", "distil-large-v3 — best English accuracy (~1.5 GB)"),
        ("large-v3", "large-v3 — best accuracy, 100 languages (~3 GB)"),
    ]

    private init() {
        engine = SpeechEngine(rawValue: defaults.string(forKey: "Engine") ?? "")
            ?? (SpeechEngine.parakeetAvailable ? .parakeet : .whisper)
        modelName = defaults.string(forKey: "ModelName") ?? "small.en"
        if let data = defaults.data(forKey: "HotkeySpec"),
           let saved = try? JSONDecoder().decode(HotkeySpec.self, from: data) {
            hotkey = saved
        } else {
            // Migrate the pre-5.4 three-choice setting.
            hotkey = HotkeySpec.legacy(defaults.string(forKey: "Hotkey")) ?? .fn
        }
        if let data = defaults.data(forKey: "CommandHotkeySpec"),
           let saved = try? JSONDecoder().decode(HotkeySpec.self, from: data) {
            commandHotkey = saved
        } else {
            commandHotkey = nil
        }
        if let data = defaults.data(forKey: "StyleSamples"),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            styleSamples = saved
        } else {
            styleSamples = [:]
        }
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: "HistoryRetention") ?? "") ?? .standard
        correctionLearningEnabled = defaults.object(forKey: "CorrectionLearningEnabled") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        llmEnabled = defaults.object(forKey: "LLMEnabled") as? Bool ?? true
        polishStrength = PolishStrength(rawValue: defaults.string(forKey: "PolishStrength") ?? "") ?? .light
        llmModel = defaults.string(forKey: "LLMModel") ?? Self.defaultLLMModel
        dictionaryText = defaults.string(forKey: "Dictionary") ?? ""
        previewEnabled = defaults.object(forKey: "PreviewEnabled") as? Bool ?? true
        soundsEnabled = defaults.object(forKey: "SoundsEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "Snippets"),
           let saved = try? JSONDecoder().decode([Snippet].self, from: data) {
            snippets = saved
        } else {
            snippets = []
        }
        if let data = defaults.data(forKey: "AppInstructions"),
           let saved = try? JSONDecoder().decode([AppInstruction].self, from: data) {
            appInstructions = saved
        } else {
            appInstructions = []
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}

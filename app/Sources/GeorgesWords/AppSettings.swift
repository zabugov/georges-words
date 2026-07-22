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

/// An app the user marked private (backlog 8.1): dictations into it are
/// never kept in history and its fields are never re-read for
/// correction learning. Dictation itself still works normally.
struct PrivateApp: Codable, Identifiable, Equatable {
    var appName: String
    var bundleID: String
    var id: String { bundleID }
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

    /// Acoustic dictionary boosting in the Parakeet engine (backlog 2.2,
    /// docs/research/dictionary-biasing-in-asr.md). Off by default: it
    /// downloads a ~100 MB helper model on first use and adds a beat to
    /// each dictation.
    @Published var dictionaryBoostEnabled: Bool {
        didSet { defaults.set(dictionaryBoostEnabled, forKey: "DictionaryBoost") }
    }

    /// Microphone chosen in Settings (6.5); nil follows the system default.
    @Published var inputDeviceUID: String? {
        didSet {
            if let inputDeviceUID {
                defaults.set(inputDeviceUID, forKey: "InputDeviceUID")
            } else {
                defaults.removeObject(forKey: "InputDeviceUID")
            }
        }
    }

    /// Apps where history and correction learning are disabled (8.1).
    @Published var privateApps: [PrivateApp] {
        didSet {
            if let data = try? JSONEncoder().encode(privateApps) {
                defaults.set(data, forKey: "PrivateApps")
            }
        }
    }

    func isPrivateApp(_ bundleID: String) -> Bool {
        let id = bundleID.lowercased()
        guard !id.isEmpty else { return false }
        return privateApps.contains { $0.bundleID == id }
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

    // Personal style matching (3.3) and per-app style notes (3.2) were
    // removed 2026-07-22 (owner decision: advanced features, revisit
    // later — see FUTURE_IMPROVEMENTS). Any saved data stays parked in
    // UserDefaults under "StyleSamples" / "AppInstructions" so a future
    // re-add finds it intact.

    /// Second hotkey: hold it and say how to change the last dictation
    /// (command mode, backlog 4.4). On by default (Right ⌥); nil = the
    /// user turned it off. The separate "off" flag lets that choice
    /// survive relaunch instead of being re-defaulted back on.
    @Published var commandHotkey: HotkeySpec? {
        didSet {
            if let commandHotkey, let data = try? JSONEncoder().encode(commandHotkey) {
                defaults.set(data, forKey: "CommandHotkeySpec")
                defaults.set(false, forKey: "CommandHotkeyOff")
            } else {
                defaults.removeObject(forKey: "CommandHotkeySpec")
                defaults.set(true, forKey: "CommandHotkeyOff")
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
        } else if defaults.bool(forKey: "CommandHotkeyOff") {
            commandHotkey = nil
        } else {
            // On by default (backlog 4.4): first run — or upgrading from
            // before command mode existed — gets Right Option.
            commandHotkey = .rightOption
        }
        historyRetention = HistoryRetention(rawValue: defaults.string(forKey: "HistoryRetention") ?? "") ?? .standard
        correctionLearningEnabled = defaults.object(forKey: "CorrectionLearningEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "PrivateApps"),
           let saved = try? JSONDecoder().decode([PrivateApp].self, from: data) {
            privateApps = saved
        } else {
            privateApps = []
        }
        // A saved ghost aggregate (selectable before 2026-07-22, and gone
        // once its owning app quits) heals back to system default.
        if let savedInput = defaults.string(forKey: "InputDeviceUID"),
           !AudioInputDevices.isTransientAggregate(uid: savedInput) {
            inputDeviceUID = savedInput
        } else {
            inputDeviceUID = nil
            defaults.removeObject(forKey: "InputDeviceUID")
        }
        dictionaryBoostEnabled = defaults.object(forKey: "DictionaryBoost") as? Bool ?? false
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

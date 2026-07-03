import AppKit
import Combine
import ServiceManagement

/// Which key you hold to dictate.
enum HotkeyChoice: String, CaseIterable, Identifiable {
    case fn
    case rightCommand
    case rightOption

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fn: return "Fn (🌐)"
        case .rightCommand: return "Right ⌘"
        case .rightOption: return "Right ⌥"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .fn: return 63
        case .rightCommand: return 54
        case .rightOption: return 61
        }
    }

    /// The modifier flag that is set while the key is held.
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn: return .function
        case .rightCommand: return .command
        case .rightOption: return .option
        }
    }
}

/// User preferences, persisted to UserDefaults, observable from SwiftUI.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// WhisperKit model identifier (prefix-matched against argmaxinc/whisperkit-coreml).
    @Published var modelName: String {
        didSet { defaults.set(modelName, forKey: "ModelName") }
    }

    @Published var hotkey: HotkeyChoice {
        didSet { defaults.set(hotkey.rawValue, forKey: "Hotkey") }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    static let modelOptions: [(name: String, label: String)] = [
        ("base.en", "base.en — fastest, rough accuracy (~150 MB)"),
        ("small.en", "small.en — good balance (default, ~500 MB)"),
        ("distil-large-v3", "distil-large-v3 — best English accuracy (~1.5 GB)"),
        ("large-v3", "large-v3 — best accuracy, 100 languages (~3 GB)"),
    ]

    private init() {
        modelName = defaults.string(forKey: "ModelName") ?? "small.en"
        hotkey = HotkeyChoice(rawValue: defaults.string(forKey: "Hotkey") ?? "") ?? .fn
        launchAtLogin = SMAppService.mainApp.status == .enabled
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

import AppKit
import UniformTypeIdentifiers

/// One-file export/import of the user's configuration (backlog 7.8):
/// settings, dictionary, snippets, per-app notes, writing samples, and
/// the private-app list. Deliberately excluded: history and the
/// learned-suggestion queue (observations of this Mac, not settings)
/// and launch-at-login (a per-machine system registration).
struct SettingsBackup: Codable {

    var version = 1
    var engine: String
    var modelName: String
    var hotkey: HotkeySpec
    var commandHotkey: HotkeySpec?
    var llmEnabled: Bool
    var polishStrength: String
    var llmModel: String
    var dictionaryText: String
    var previewEnabled: Bool
    var soundsEnabled: Bool
    var snippets: [Snippet]
    var appInstructions: [AppInstruction]
    var styleSamples: [String: String]
    var privateApps: [PrivateApp]
    var historyRetention: String
    var correctionLearningEnabled: Bool
    var inputDeviceUID: String?

    @MainActor
    static func capture(from settings: AppSettings) -> SettingsBackup {
        SettingsBackup(
            engine: settings.engine.rawValue,
            modelName: settings.modelName,
            hotkey: settings.hotkey,
            commandHotkey: settings.commandHotkey,
            llmEnabled: settings.llmEnabled,
            polishStrength: settings.polishStrength.rawValue,
            llmModel: settings.llmModel,
            dictionaryText: settings.dictionaryText,
            previewEnabled: settings.previewEnabled,
            soundsEnabled: settings.soundsEnabled,
            snippets: settings.snippets,
            appInstructions: settings.appInstructions,
            styleSamples: settings.styleSamples,
            privateApps: settings.privateApps,
            historyRetention: settings.historyRetention.rawValue,
            correctionLearningEnabled: settings.correctionLearningEnabled,
            inputDeviceUID: settings.inputDeviceUID
        )
    }

    /// Every assignment goes through the published properties, so the
    /// normal didSet persistence and AppDelegate observers (model
    /// reload, hotkey reinstall…) react exactly as if the user had
    /// changed each setting by hand.
    @MainActor
    func apply(to settings: AppSettings) {
        if let value = SpeechEngine(rawValue: engine) { settings.engine = value }
        settings.modelName = modelName
        settings.hotkey = hotkey
        settings.commandHotkey = commandHotkey
        settings.llmEnabled = llmEnabled
        if let value = PolishStrength(rawValue: polishStrength) { settings.polishStrength = value }
        settings.llmModel = llmModel
        settings.dictionaryText = dictionaryText
        settings.previewEnabled = previewEnabled
        settings.soundsEnabled = soundsEnabled
        settings.snippets = snippets
        settings.appInstructions = appInstructions
        settings.styleSamples = styleSamples
        settings.privateApps = privateApps
        if let value = HistoryRetention(rawValue: historyRetention) { settings.historyRetention = value }
        settings.correctionLearningEnabled = correctionLearningEnabled
        settings.inputDeviceUID = inputDeviceUID
    }

    // MARK: - Panels

    @MainActor
    static func exportViaPanel(_ settings: AppSettings) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "GeorgesWords-settings.json"
        panel.title = "Export Settings"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(capture(from: settings)) else { return }
        try? data.write(to: url)
    }

    /// Returns a short human-readable outcome for the Settings pane.
    @MainActor
    static func importViaPanel(_ settings: AppSettings) -> String {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "Import Settings"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return "" }
        guard let data = try? Data(contentsOf: url),
              let backup = try? JSONDecoder().decode(SettingsBackup.self, from: data)
        else { return "That file doesn't look like a George's Words settings export." }
        backup.apply(to: settings)
        return "Settings imported."
    }
}

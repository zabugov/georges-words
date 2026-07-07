import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var ollamaRunning: Bool?
    @State private var installedModels: [String]?
    /// Which tone profile's writing sample is being edited (3.3).
    @State private var styleTone: ToneProfile = .casual
    /// Available input devices for the microphone picker (6.5).
    @State private var inputDevices: [AudioInputDevices.Device] = []
    /// Outcome line after an import attempt (7.8).
    @State private var importFeedback = ""

    private struct RunningApp: Identifiable {
        let name: String
        let bundleID: String
        var id: String { bundleID }
    }

    /// Regular apps currently running, minus ones that already have a note.
    private var runningApps: [RunningApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier?.lowercased(), !id.isEmpty,
                      let name = app.localizedName
                else { return nil }
                guard seen.insert(id).inserted else { return nil }
                guard !settings.appInstructions.contains(where: { $0.bundleID == id }) else { return nil }
                return RunningApp(name: name, bundleID: id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section("Speech recognition") {
                if SpeechEngine.parakeetAvailable {
                    Picker("Engine", selection: $settings.engine) {
                        ForEach(SpeechEngine.available) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    if settings.engine == .parakeet {
                        Text("Parakeet v3 (NVIDIA, via FluidAudio): much faster on Apple Silicon, top-ranked accuracy. English, 24 European languages, and Japanese. One-time ~600 MB download.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                // Only meaningful when Whisper is the engine — hidden
                // entirely otherwise, not just disabled.
                if settings.engine == .whisper || !SpeechEngine.parakeetAvailable {
                    Picker("Whisper model", selection: $settings.modelName) {
                        ForEach(AppSettings.modelOptions, id: \.name) { option in
                            Text(option.label).tag(option.name)
                        }
                    }
                    Text("Changing the model triggers a one-time download, then everything runs offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Microphone") {
                Picker("Input", selection: $settings.inputDeviceUID) {
                    Text("System default").tag(String?.none)
                    ForEach(inputDevices) { device in
                        Text(device.name).tag(String?.some(device.uid))
                    }
                    // Keep a remembered-but-unplugged device selectable so
                    // the picker never shows a blank selection.
                    if let uid = settings.inputDeviceUID, !inputDevices.contains(where: { $0.uid == uid }) {
                        Text("Remembered device (not connected)").tag(String?.some(uid))
                    }
                }
                Text("System default follows whatever macOS is using. If dictations come out silent, check the right microphone is selected here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onAppear { inputDevices = AudioInputDevices.list() }

            Section("Hotkeys") {
                HotkeyRecorderField(title: "Hold to dictate", spec: $settings.hotkey)
                if settings.hotkey == .fn {
                    Text("Tip: set System Settings → Keyboard → “Press 🌐 key” to “Do Nothing” so holding Fn doesn’t open the emoji picker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Click Change… and press any key — modifier and function keys work best. Letter keys still type into the focused app while held.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                OptionalHotkeyRecorderField(
                    title: "Hold for a voice command",
                    spec: $settings.commandHotkey,
                    conflictsWith: settings.hotkey
                )
                Text("Hold it and say how to change your last dictation — “make it more formal”, “remove the word actually”, “translate to French”. Runs on the same local AI as polish; nothing leaves your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Live preview while speaking", isOn: $settings.previewEnabled)
                Text("Shows a rolling transcript in the pill as you talk. Costs some extra compute while recording.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Sound on record start/stop", isOn: $settings.soundsEnabled)
            }

            Section("AI polish (local)") {
                Toggle("Polish transcripts with a local LLM", isOn: $settings.llmEnabled)

                Picker("Polish style", selection: $settings.polishStrength) {
                    ForEach(PolishStrength.allCases) { strength in
                        Text(strength.displayName).tag(strength)
                    }
                }
                .disabled(!settings.llmEnabled)
                Text(settings.polishStrength == .light
                     ? "Removes ums/uhs and false starts, fixes punctuation, applies self-corrections — otherwise keeps your exact words. Outputs that stray from your wording are rejected."
                     : "Restructures sentences and matches tone to the app you're dictating into. May reword what you said.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if ollamaRunning == nil {
                    Text("Checking the polish engine…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if ollamaRunning == false {
                    Text("The polish engine isn’t running yet — it starts and sets itself up automatically (progress under Troubleshooting). Dictation still works meanwhile, with rule-based cleanup instead of the full rewrite.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if let models = installedModels, models.isEmpty {
                    Text("The engine is running and downloading its first model — check Troubleshooting for progress, then click Refresh.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if let models = installedModels {
                    Picker("Polish model", selection: $settings.llmModel) {
                        ForEach(models, id: \.self) { name in
                            Text(name).tag(name)
                        }
                        // Keep a remembered-but-deleted model selectable so the
                        // picker never shows a blank selection.
                        if !settings.llmModel.isEmpty && !models.contains(settings.llmModel) {
                            Text("\(settings.llmModel) — not downloaded").tag(settings.llmModel)
                        }
                    }
                    .disabled(!settings.llmEnabled)
                    if !settings.llmModel.isEmpty && !models.contains(settings.llmModel) {
                        Text("This model isn’t downloaded yet — the engine fetches it automatically; watch Troubleshooting, then Refresh.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Label("Polish engine running — \(models.count) model\(models.count == 1 ? "" : "s") available", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                Button("Refresh model list") {
                    Task { await refreshOllama() }
                }


                Text("Fixes self-corrections (“Tuesday — no wait, Friday”), sentence structure, and tone, matched to the app you’re dictating into. The app runs its own private engine, entirely on this Mac — nothing is installed system-wide and nothing is sent anywhere. Its files live in Application Support → GeorgesWords → PolishEngine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Your writing style") {
                Picker("Writing for", selection: $styleTone) {
                    ForEach(ToneProfile.allCases, id: \.rawValue) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
                TextEditor(text: Binding(
                    get: { settings.styleSamples[styleTone.rawValue] ?? "" },
                    set: { settings.styleSamples[styleTone.rawValue] = $0 }
                ))
                .font(.body)
                .frame(minHeight: 90)
                .disabled(!settings.llmEnabled)
                Text("Paste a short sample of how YOU write in this kind of app — a real chat message, a real email. Full polish will match its voice instead of a generic style. Stays on this Mac; leave empty to skip. Applies with the Full polish style only.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Picker("Keep dictation history", selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases) { retention in
                        Text(retention.displayName).tag(retention)
                    }
                }
                Text("History only ever exists on this Mac — this controls how long even that local copy is kept. Switching to “Keep nothing” erases it immediately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("Learn corrections from your edits", isOn: $settings.correctionLearningEnabled)
                Text("After inserting a dictation, the app briefly re-reads that text field to notice fixes you make (all on-device, suggestions only). Turn this off and it never looks back at the field; the manual “Fix the last transcript” box in Dictionary still works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(settings.privateApps) { app in
                    HStack {
                        Text(app.appName.isEmpty ? app.bundleID : app.appName)
                        Spacer()
                        Button {
                            settings.privateApps.removeAll { $0.bundleID == app.bundleID }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add Private App…") {
                    ForEach(privateAppCandidates) { app in
                        Button(app.name) {
                            settings.privateApps.append(PrivateApp(appName: app.name, bundleID: app.bundleID))
                        }
                    }
                }
                Text("Dictation into a private app works normally, but nothing said there is kept in History and its text fields are never re-read for correction learning.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Per-app style notes") {
                ForEach($settings.appInstructions) { $entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.appName.isEmpty ? entry.bundleID : entry.appName)
                                .fontWeight(.medium)
                            Spacer()
                            Button {
                                settings.appInstructions.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        TextField("e.g. use markdown headings; keep it terse", text: $entry.instruction)
                        Text(entry.bundleID)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
                Menu("Add App…") {
                    ForEach(runningApps) { app in
                        Button(app.name) {
                            settings.appInstructions.append(
                                AppInstruction(appName: app.name, bundleID: app.bundleID, instruction: "")
                            )
                        }
                    }
                }
                Text("Your own style notes for specific apps — “use markdown headings”, “sign off with -Z”. Applied on top of the built-in tone when the polish style is “Rewrite for clarity”. The menu lists apps that are currently running.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Backup") {
                HStack {
                    Button("Export Settings…") { SettingsBackup.exportViaPanel(settings) }
                    Button("Import Settings…") { importFeedback = SettingsBackup.importViaPanel(settings) }
                    if !importFeedback.isEmpty {
                        Text(importFeedback)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("One file with your settings, dictionary, snippets, per-app notes, writing samples, and private-app list — for moving to a new Mac or keeping a backup. History and learned suggestions stay on this Mac. Nothing is uploaded anywhere.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .task { await refreshOllama() }
    }

    private struct HotkeyRecorderField: View {
        let title: String
        @Binding var spec: HotkeySpec
        @StateObject private var capture = HotkeyCapture()

        var body: some View {
            LabeledContent(title) {
                HStack(spacing: 8) {
                    Text(capture.isRecording ? "Press any key… (Esc to cancel)" : spec.displayName)
                        .foregroundStyle(capture.isRecording ? .secondary : .primary)
                    Button(capture.isRecording ? "Cancel" : "Change…") {
                        if capture.isRecording {
                            capture.cancel()
                        } else {
                            capture.begin { spec = $0 }
                        }
                    }
                    Menu("Presets") {
                        Button("Fn (🌐)") { spec = .fn }
                        Button("Right ⌘") { spec = .rightCommand }
                        Button("Right ⌥") { spec = .rightOption }
                    }
                    .fixedSize()
                }
            }
            .onDisappear { capture.cancel() }
        }
    }

    /// Running apps not yet marked private (8.1) — same source as the
    /// per-app notes menu.
    private var privateAppCandidates: [RunningApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier?.lowercased(), !id.isEmpty,
                      let name = app.localizedName
                else { return nil }
                guard seen.insert(id).inserted else { return nil }
                guard !settings.privateApps.contains(where: { $0.bundleID == id }) else { return nil }
                return RunningApp(name: name, bundleID: id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Like HotkeyRecorderField, but for an optional hotkey: nil = the
    /// feature is off. Refuses the dictation key — one key, one job.
    private struct OptionalHotkeyRecorderField: View {
        let title: String
        @Binding var spec: HotkeySpec?
        let conflictsWith: HotkeySpec
        @StateObject private var capture = HotkeyCapture()
        @State private var conflictWarning = false

        var body: some View {
            LabeledContent(title) {
                HStack(spacing: 8) {
                    Text(capture.isRecording ? "Press any key… (Esc to cancel)" : (spec?.displayName ?? "Off"))
                        .foregroundStyle(capture.isRecording || spec == nil ? .secondary : .primary)
                    Button(capture.isRecording ? "Cancel" : (spec == nil ? "Set…" : "Change…")) {
                        if capture.isRecording {
                            capture.cancel()
                        } else {
                            conflictWarning = false
                            capture.begin { new in
                                if new == conflictsWith {
                                    conflictWarning = true
                                } else {
                                    spec = new
                                }
                            }
                        }
                    }
                    if spec != nil {
                        Button("Turn Off") { spec = nil }
                    }
                }
            }
            .onDisappear { capture.cancel() }
            if conflictWarning {
                Text("That's already the dictation key — pick a different one.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func refreshOllama() async {
        ollamaRunning = nil
        installedModels = nil
        let running = await LLMFormatter.ollamaIsRunning()
        ollamaRunning = running
        guard running else { return }
        let models = await LLMFormatter.installedModels() ?? []
        installedModels = models

        // Nothing selected yet → pick the default if it's downloaded,
        // otherwise the first available model.
        if settings.llmModel.trimmingCharacters(in: .whitespaces).isEmpty, !models.isEmpty {
            settings.llmModel = models.contains(AppSettings.defaultLLMModel)
                ? AppSettings.defaultLLMModel
                : models[0]
        }
    }
}

import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var ollamaRunning: Bool?
    @State private var installedModels: [String]?

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

            Section("Hotkeys") {
                HotkeyRecorderField(title: "Hold to dictate", spec: $settings.hotkey)
                if settings.hotkey == .fn {
                    Text("Tip: set System Settings → Keyboard → “Press 🌐 key” to “Do Nothing” so holding Fn doesn’t open the emoji picker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                HotkeyRecorderField(title: "Hold for command mode", spec: $settings.commandHotkey)
                Text("Click Change… and press any key — modifier and function keys work best. Letter keys still type into the focused app while held.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if settings.commandHotkey == settings.hotkey {
                    Text("⚠️ Same key as dictation — command mode is disabled until you pick a different key.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    Text("Select text anywhere, hold \(settings.commandHotkey.displayName), and speak an instruction — “make this shorter”, “make it a bulleted list”, “translate to French”. Requires the local LLM (Ollama).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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
                    Text("Checking for Ollama…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if ollamaRunning == false {
                    Text("Ollama isn’t running. Install it from ollama.com, then run:  ollama pull \(settings.effectiveLLMModel)\nDictation still works without it — you just get rule-based cleanup instead of the full rewrite.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if let models = installedModels, models.isEmpty {
                    Text("Ollama is running but has no models downloaded yet. In Terminal:  ollama pull \(AppSettings.defaultLLMModel)  — then click Refresh.")
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
                        Text("This model isn’t downloaded anymore — pick another, or run:  ollama pull \(settings.llmModel)")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Label("Ollama detected — \(models.count) model\(models.count == 1 ? "" : "s") available", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }

                Button("Refresh model list") {
                    Task { await refreshOllama() }
                }

                Text("The polish engine manages itself: a normal Ollama install is used when it's running; otherwise the app runs its own private copy (downloaded once, ~120 MB + the model) and keeps it out of sight. Setup progress appears under Troubleshooting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Fixes self-corrections (“Tuesday — no wait, Friday”), sentence structure, and tone, matched to the app you’re dictating into. Runs entirely on this Mac via Ollama (localhost); nothing is sent anywhere. Download more models with “ollama pull <name>”, then Refresh.")
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

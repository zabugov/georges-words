import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var ollamaRunning: Bool?
    @State private var installedModels: [String]?

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
                Picker("Whisper model", selection: $settings.modelName) {
                    ForEach(AppSettings.modelOptions, id: \.name) { option in
                        Text(option.label).tag(option.name)
                    }
                }
                .disabled(SpeechEngine.parakeetAvailable && settings.engine != .whisper)
                Text("Changing the model triggers a one-time download, then everything runs offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkeys") {
                Picker("Hold to dictate", selection: $settings.hotkey) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
                if settings.hotkey == .fn {
                    Text("Tip: set System Settings → Keyboard → “Press 🌐 key” to “Do Nothing” so holding Fn doesn’t open the emoji picker.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Picker("Hold for command mode", selection: $settings.commandHotkey) {
                    ForEach(HotkeyChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice)
                    }
                }
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

                Text("Fixes self-corrections (“Tuesday — no wait, Friday”), sentence structure, and tone, matched to the app you’re dictating into. Runs entirely on this Mac via Ollama (localhost); nothing is sent anywhere. Download more models with “ollama pull <name>”, then Refresh.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Personal dictionary") {
                TextEditor(text: $settings.dictionaryText)
                    .font(.body.monospaced())
                    .frame(height: 90)
                Text("One term per line — names, jargon, product words. Their exact spelling is enforced in every transcript.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Snippets") {
                ForEach($settings.snippets) { $snippet in
                    HStack {
                        TextField("Say…", text: $snippet.trigger)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                        TextField("Insert…", text: $snippet.expansion)
                        Button {
                            settings.snippets.removeAll { $0.id == snippet.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add Snippet") {
                    settings.snippets.append(Snippet(trigger: "", expansion: ""))
                }
                Text("Voice shortcuts: saying the trigger phrase inserts the expansion exactly as written — e.g. “my sign off” → your full email signature.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 660)
        .task { await refreshOllama() }
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

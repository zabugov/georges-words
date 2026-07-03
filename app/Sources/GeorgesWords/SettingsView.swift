import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var ollamaRunning: Bool?

    var body: some View {
        Form {
            Section("Speech recognition") {
                Picker("Speech model", selection: $settings.modelName) {
                    ForEach(AppSettings.modelOptions, id: \.name) { option in
                        Text(option.label).tag(option.name)
                    }
                }
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
                TextField("Ollama model", text: $settings.llmModel, prompt: Text(AppSettings.defaultLLMModel))
                    .disabled(!settings.llmEnabled)
                if settings.llmModel.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Empty — using the default (\(AppSettings.defaultLLMModel)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                switch ollamaRunning {
                case .some(true):
                    Label("Ollama detected on this Mac", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                case .some(false):
                    Text("Ollama isn’t running. Install it from ollama.com, then run:  ollama pull \(settings.effectiveLLMModel)\nDictation still works without it — you just get rule-based cleanup instead of the full rewrite.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                case .none:
                    Text("Checking for Ollama…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Fixes self-corrections (“Tuesday — no wait, Friday”), sentence structure, and tone, matched to the app you’re dictating into. Runs entirely on this Mac via Ollama (localhost); nothing is sent anywhere.")
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
        .task { ollamaRunning = await LLMFormatter.ollamaIsRunning() }
    }
}

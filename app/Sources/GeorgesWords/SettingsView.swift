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

            Section("Hotkey") {
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
            }

            Section("AI polish (local)") {
                Toggle("Polish transcripts with a local LLM", isOn: $settings.llmEnabled)
                TextField("Ollama model", text: $settings.llmModel)
                    .disabled(!settings.llmEnabled)

                switch ollamaRunning {
                case .some(true):
                    Label("Ollama detected on this Mac", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                case .some(false):
                    Text("Ollama isn’t running. Install it from ollama.com, then run:  ollama pull \(settings.llmModel)\nDictation still works without it — you just get rule-based cleanup instead of the full rewrite.")
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

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
        .task { ollamaRunning = await LLMFormatter.ollamaIsRunning() }
    }
}

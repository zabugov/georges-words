import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Speech model", selection: $settings.modelName) {
                    ForEach(AppSettings.modelOptions, id: \.name) { option in
                        Text(option.label).tag(option.name)
                    }
                }
                Text("Changing the model triggers a one-time download, then everything runs offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
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

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

/// First-run wizard (backlog 5.2): welcome → microphone → accessibility →
/// 🌐 key → engine/polish → try it. Shown once on fresh installs; existing
/// installs (any prior dictations) never see it.
struct OnboardingView: View {

    enum Step: Int, CaseIterable {
        case welcome
        case microphone
        case accessibility
        case globeKey
        case engine
        case practice
    }

    let onFinish: () -> Void

    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var managedEngine = ManagedOllama.shared
    @State private var step: Step = .welcome
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted = AXIsProcessTrusted()
    @State private var practiceText = ""

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(28)
            Divider()
            footer
                .padding(16)
        }
        .frame(width: 560, height: 600)
        .task {
            // Live permission status while the wizard is open — grants
            // happen in System Settings, outside our control.
            while !Task.isCancelled {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                axGranted = AXIsProcessTrusted()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            page(
                icon: nil,
                title: "Welcome to George's Words",
                subtitle: "Hold a key, speak, release — clean text appears wherever you're typing. Everything runs on this Mac: audio and transcripts never leave it. No account, no cloud."
            ) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("The next few steps take about two minutes: two macOS permissions, one keyboard setting, and a test run.")
                    .foregroundStyle(.secondary)
            }

        case .microphone:
            page(
                icon: "mic",
                title: "Microphone",
                subtitle: "Needed to hear you while you hold the dictation key. Audio is transcribed on this Mac and never recorded to disk or sent anywhere."
            ) {
                switch micStatus {
                case .authorized:
                    Label("Microphone access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .notDetermined:
                    Button("Allow Microphone Access") {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            DispatchQueue.main.async {
                                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                            }
                        }
                    }
                    .controlSize(.large)
                default:
                    Label("Access was denied — enable GeorgesWords under Microphone in System Settings, then come back.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Open System Settings") {
                        Self.openPrivacyPane("Privacy_Microphone")
                    }
                }
            }

        case .accessibility:
            page(
                icon: "keyboard",
                title: "Accessibility",
                subtitle: "Lets the app watch for your dictation key and place finished text at your cursor in other apps. macOS calls this \"Accessibility\" access."
            ) {
                if axGranted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant Accessibility Access") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                        Self.openPrivacyPane("Privacy_Accessibility")
                    }
                    .controlSize(.large)
                    Text("System Settings will open — turn on GeorgesWords in the list, then come back here. This page updates by itself.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

        case .globeKey:
            page(
                icon: "globe",
                title: "Free up the 🌐 key",
                subtitle: "The dictation key is Fn (🌐), bottom-left of the keyboard. By default macOS also uses it for the emoji picker — one setting fixes that."
            ) {
                Text("In Keyboard settings, set **“Press 🌐 key to”** to **“Do Nothing”**.")
                Button("Open Keyboard Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.large)
                Text("Prefer a different key? You can pick any key later in Settings → Hotkeys.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .engine:
            page(
                icon: "cpu",
                title: "Speech engine",
                subtitle: "The first launch downloads the speech model (one-time, ~600 MB). It runs on this Mac's Neural Engine — that download is the only network use dictation ever makes."
            ) {
                HStack(spacing: 8) {
                    if status.health == .loading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: status.health == .ready ? "checkmark.circle.fill" : "hourglass")
                            .foregroundStyle(status.health == .ready ? .green : .orange)
                    }
                    Text(status.health == .ready ? "Speech model ready" : status.statusText)
                }
                Divider()
                HStack(spacing: 8) {
                    switch managedEngine.phase {
                    case .ready, .deferringToUserOllama:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("AI polish ready")
                    case .failed:
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("AI polish setup hit a snag — see Troubleshooting later; dictation works regardless")
                    case .off:
                        Image(systemName: "sparkles")
                            .foregroundStyle(.secondary)
                        Text("AI polish sets itself up automatically")
                    default:
                        ProgressView()
                            .controlSize(.small)
                        Text("Setting up AI polish in the background…")
                    }
                }
                Text("Polish tidies grammar and self-corrections with a small language model (~1 GB, downloaded once) — also fully on this Mac. Dictation works while it sets up, with basic cleanup in the meantime.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .practice:
            page(
                icon: "waveform",
                title: "Try it",
                subtitle: "Click into the box below, hold \(settings.hotkey.displayName), say a sentence, and release."
            ) {
                TextEditor(text: $practiceText)
                    .font(.body)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                if practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("A pill appears at the bottom of the screen while you speak. Quick-tap the key instead of holding to dictate hands-free.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Label("That's it — you're set. This works in any app: mail, notes, chat, anywhere you can type.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func page<Content: View>(
        icon: String?,
        title: String,
        subtitle: String,
        @ViewBuilder extra: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
            }
            Text(title)
                .font(.title.bold())
            Text(.init(subtitle))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Navigation

    private var footer: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .welcome
                }
            }
            Button("Skip Setup") { onFinish() }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            Spacer()
            Text("\(step.rawValue + 1) of \(Step.allCases.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Button(step == .practice ? "Finish" : (step == .welcome ? "Get Started" : "Continue")) {
                if step == .practice {
                    onFinish()
                } else {
                    step = Step(rawValue: step.rawValue + 1) ?? .practice
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

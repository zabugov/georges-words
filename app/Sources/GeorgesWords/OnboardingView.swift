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
        .frame(width: 520)
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
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 110, height: 110)
                Text("Welcome to George's Words.")
                    .font(.title.bold())
                FnKeycap()
                Text("Once this quick setup is done, you'll talk instead of type: hold down the **fn key** — the bottom-left corner of your keyboard — say what you want to write, and let go. Your words will appear right where you were typing, spelled and punctuated properly.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Everything happens privately on this computer. Your voice never leaves it — nobody can hear what you say except you.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Setup takes about two minutes.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

        case .microphone:
            page(
                icon: "mic",
                title: "Microphone",
                subtitle: "Needed to hear you while you hold the fn key. Audio is turned into text on this Mac and never recorded to disk or sent anywhere."
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
                subtitle: "This lets the app notice when you hold the fn key and place your words where you're typing. macOS calls this \"Accessibility\" access."
            ) {
                if axGranted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        stepRow(1, "Click **Open Accessibility Settings** below. The right page opens by itself.")
                        stepRow(2, "Find **GeorgesWords** in the list of apps.")
                        stepRow(3, "Click its switch so it turns blue and slides right — like this:")
                    }
                    .multilineTextAlignment(.leading)
                    AccessibilityRowMock()
                    VStack(alignment: .leading, spacing: 10) {
                        stepRow(4, "If your Mac asks for your login password, that's normal — enter it.")
                    }
                    .multilineTextAlignment(.leading)
                    Button("Open Accessibility Settings") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                        Self.openPrivacyPane("Privacy_Accessibility")
                    }
                    .controlSize(.large)
                    Text("Then come back to this window — it notices on its own and shows a green checkmark here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

        case .globeKey:
            page(
                icon: "globe",
                title: "Free up the fn key",
                subtitle: "George's Words listens while you hold the fn key. By default macOS also uses that key for the emoji picker — one setting fixes the overlap."
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
                icon: "arrow.down.circle",
                title: "Two quick downloads",
                subtitle: "The app is downloading the two things it needs — one to turn your speech into words (about 600 MB), and one to tidy those words up (about 1 GB). This happens once, by itself."
            ) {
                HStack(spacing: 8) {
                    if status.health == .ready {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Turning speech into words — ready")
                    } else {
                        ProgressView()
                            .controlSize(.small)
                        Text("Turning speech into words — downloading…")
                    }
                }
                HStack(spacing: 8) {
                    switch managedEngine.phase {
                    case .ready:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Tidying your words — ready")
                    case .failed:
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text("Tidying your words — having trouble, but you can dictate anyway")
                    case .downloadingModel(let percent):
                        ProgressView()
                            .controlSize(.small)
                        Text("Tidying your words — downloading\(percent.map { " (\($0)%)" } ?? "")…")
                    default:
                        ProgressView()
                            .controlSize(.small)
                        Text("Tidying your words — downloading…")
                    }
                }
                Text("You don't have to wait — feel free to continue.")
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
        VStack(spacing: 14) {
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
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
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

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(.init(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A drawn replica of the System Settings row the user must switch on —
/// shows exactly what to look for, in the current light/dark appearance.
struct AccessibilityRowMock: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 26, height: 26)
            Text("GeorgesWords")
            Spacer()
            Capsule()
                .fill(.blue)
                .frame(width: 40, height: 24)
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .padding(2)
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
    }
}

/// A drawn Mac fn keycap (🌐 bottom-left, "fn" top-right, like the real
/// key) — crisper than a bitmap at any size and matches light/dark mode.
struct FnKeycap: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
            VStack {
                HStack {
                    Spacer()
                    Text("fn")
                        .font(.system(size: 14, weight: .medium))
                }
                Spacer()
                HStack {
                    Image(systemName: "globe")
                        .font(.system(size: 17))
                    Spacer()
                }
            }
            .padding(10)
            .foregroundStyle(.secondary)
        }
        .frame(width: 68, height: 68)
        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
    }
}

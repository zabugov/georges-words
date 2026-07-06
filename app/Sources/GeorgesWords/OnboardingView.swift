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
    /// Fired when the Try-it page appears — the moment dictation should
    /// come alive. Before that, holding fn must do nothing.
    let onReachedPractice: () -> Void

    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var managedEngine = ManagedOllama.shared
    @State private var step: Step = .welcome
    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted = AXIsProcessTrusted()
    @State private var fnKeyFreed = OnboardingView.fnKeyIsFreed()
    @State private var practiceText = ""
    @FocusState private var practiceBoxFocused: Bool

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
        .onChange(of: step) { _, newStep in
            // The cursor should already be waiting in the practice box —
            // asking a first-time user to "click into the box" first was
            // one instruction too many. Small delay so the page transition
            // finishes before focus lands.
            guard newStep == .practice else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                practiceBoxFocused = true
            }
        }
        .task {
            // Live permission status while the wizard is open — grants
            // happen in System Settings, outside our control.
            while !Task.isCancelled {
                micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                axGranted = AXIsProcessTrusted()
                fnKeyFreed = Self.fnKeyIsFreed()
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                default:
                    VStack(alignment: .leading, spacing: 10) {
                        stepRow(1, "Click **Open Microphone Settings** below. The right page opens by itself.")
                        stepRow(2, "Find **GeorgesWords** in the list of apps.")
                        stepRow(3, "Click its switch so it turns blue and slides right — like this:")
                    }
                    .multilineTextAlignment(.leading)
                    PermissionRowMock()
                    Button("Open Microphone Settings") {
                        Self.openPrivacyPane("Privacy_Microphone")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("Then come back to this window — it notices on its own and shows a green checkmark here. (If it doesn't update, quit the app and open it again.)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        case .accessibility:
            page(
                icon: "keyboard",
                title: "Accessibility",
                subtitle: "This lets the app notice when you hold the fn key and place your words where you're typing. Your Mac calls this \"Accessibility\" access."
            ) {
                if axGranted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        stepRow(1, "Click **Ask for Access** below.")
                        stepRow(2, "Your Mac will show a message — click **Open System Settings** on it.")
                        stepRow(3, "Find **GeorgesWords** in the list and click its switch so it turns blue — like this:")
                    }
                    .multilineTextAlignment(.leading)
                    PermissionRowMock()
                    VStack(alignment: .leading, spacing: 10) {
                        stepRow(4, "If your Mac asks for your login password, that's normal — enter it.")
                    }
                    .multilineTextAlignment(.leading)
                    // One path only: the system dialog's own button opens the
                    // right Settings page. Deep-linking ourselves at the same
                    // time buried that dialog behind System Settings, where
                    // it lingered unanswered (Zach hit exactly this).
                    Button("Ask for Access") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("Then come back to this window — it notices on its own and shows a green checkmark here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("No message appeared? Open the settings page directly") {
                        Self.openPrivacyPane("Privacy_Accessibility")
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }

        case .globeKey:
            page(
                icon: "globe",
                title: "Free up the fn key",
                subtitle: "George's Words listens while you hold the fn key. Your Mac normally uses that key for the emoji picker — one quick setting change gives the key to George's Words instead."
            ) {
                if fnKeyFreed {
                    Label("The 🌐 key is set to “Do Nothing” — it's all yours", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("In Keyboard settings, find **“Press 🌐 key to”** and choose **“Do Nothing”** — so it looks like this:")
                        .fixedSize(horizontal: false, vertical: true)
                    GlobeKeyRowMock()
                    Button("Open Keyboard Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("Then come back — this page notices on its own.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Prefer a different key? You can pick any key later in Settings → Hotkeys.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                icon: nil,
                title: "Try it",
                subtitle: "Hold down this key, say a sentence, and let go:"
            ) {
                FnKeycap()
                TextEditor(text: $practiceText)
                    .font(.body)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                    .focused($practiceBoxFocused)
                if practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Your words will appear on the screen as you speak. When you let go, they'll be right where you would have typed them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("That's it — you're set. This works in any app: mail, notes, chat, anywhere you can type.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
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

    /// True while the current page has an unfinished permission action —
    /// its in-page button should be the only blue one on screen.
    private var pageActionPending: Bool {
        switch step {
        case .microphone: return micStatus != .authorized
        case .accessibility: return !axGranted
        case .globeKey: return !fnKeyFreed
        default: return false
        }
    }

    /// Whether "Press 🌐 key to" is set to "Do Nothing" (AppleFnUsageType
    /// 0). macOS stores it in the HIToolbox domain, refreshed before each
    /// read so the page updates live while System Settings is open.
    static func fnKeyIsFreed() -> Bool {
        CFPreferencesAppSynchronize("com.apple.HIToolbox" as CFString)
        let value = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
        return (value as? Int) == 0
    }

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
            let primaryTitle = step == .practice ? "Finish" : (step == .welcome ? "Get Started" : "Continue")
            let advance = {
                if step == .practice {
                    onFinish()
                } else {
                    let next = Step(rawValue: step.rawValue + 1) ?? .practice
                    step = next
                    if next == .practice {
                        onReachedPractice()
                    }
                }
            }
            if pageActionPending {
                Button(primaryTitle, action: advance)
            } else {
                Button(primaryTitle, action: advance)
                    .keyboardShortcut(.defaultAction)
            }
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
/// Tilted with an EXAMPLE tag so it reads as an illustration, not a
/// clickable control. Used by both the Microphone and Accessibility pages.
struct PermissionRowMock: View {
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
        .exampleSticker()
    }
}

/// The Keyboard-settings row the 🌐-key page asks the user to change,
/// shown in its finished state ("Do Nothing").
struct GlobeKeyRowMock: View {
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                Text("Press")
                Image(systemName: "globe")
                Text("key to")
            }
            Spacer()
            HStack(spacing: 6) {
                Text("Do Nothing")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlColor)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
        .exampleSticker()
    }
}

extension View {
    /// Illustration treatment for drawn Settings replicas: slight tilt,
    /// an EXAMPLE tag, and no interactivity — a picture, not a control.
    func exampleSticker() -> some View {
        self
            .overlay(alignment: .topTrailing) {
                Text("EXAMPLE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.orange))
                    .rotationEffect(.degrees(8))
                    .offset(x: 12, y: -8)
            }
            .rotationEffect(.degrees(-2))
            .allowsHitTesting(false)
            .padding(.vertical, 4)
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

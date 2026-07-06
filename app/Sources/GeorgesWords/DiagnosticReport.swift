import AppKit
import AVFoundation

/// Backlog 9.5: one file a user can send instead of answering twenty
/// questions. Versions, permission states, engine status, and settings
/// FLAGS only — never audio, transcripts, dictionary contents, or
/// history. The debug.log tail is included; it is stage/length-only by
/// design (see DebugLog).
enum DiagnosticReport {

    @MainActor
    static func generate() -> String {
        let settings = AppSettings.shared
        var lines: [String] = []

        lines.append("George's Words — diagnostic report")
        lines.append("Generated: \(Date().formatted(date: .abbreviated, time: .standard))")
        lines.append("App: \(AboutView.version)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

        // Update channel: source checkout (git) or installed app (Sparkle).
        let repoCandidate = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fromCheckout = FileManager.default.fileExists(
            atPath: repoCandidate.appendingPathComponent("app/build.sh").path
        )
        lines.append("Install: \(fromCheckout ? "source checkout (git updates)" : "app bundle (Sparkle updates)")")
        // Category only, never the actual path — reports get attached to
        // public issues, and paths leak usernames and folder names.
        let location: String
        if fromCheckout {
            location = "source checkout"
        } else if Bundle.main.bundleURL.path.hasPrefix("/Applications/") {
            location = "/Applications"
        } else {
            location = "other (path withheld)"
        }
        lines.append("Location: \(location)")
        lines.append("")

        lines.append("Microphone permission: \(describe(AVCaptureDevice.authorizationStatus(for: .audio)))")
        lines.append("Accessibility permission: \(AXIsProcessTrusted() ? "granted" : "NOT granted")")
        lines.append("")

        lines.append("Speech engine: \(settings.engine.rawValue)")
        lines.append("Whisper model (fallback engine): \(settings.modelName)")
        lines.append("AI polish enabled: \(settings.llmEnabled)")
        lines.append("Polish style: \(settings.polishStrength.rawValue)")
        lines.append("Polish model: \(settings.effectiveLLMModel)")
        lines.append("Polish engine state: \(describe(ManagedOllama.shared.phase))")
        lines.append("")

        lines.append("Hotkey: \(settings.hotkey.displayName)")
        lines.append("Live preview: \(settings.previewEnabled)")
        lines.append("Sounds: \(settings.soundsEnabled)")
        lines.append("Launch at login: \(settings.launchAtLogin)")
        lines.append("Dictionary entries: \(settings.dictionaryTerms.count)")
        lines.append("Snippets: \(settings.snippets.count)")
        lines.append("Per-app notes: \(settings.appInstructions.count)")
        lines.append("History entries: \(HistoryStore.shared.entries.count)")
        lines.append("")

        lines.append("--- recent diagnostics (debug.log tail; contains no dictated text) ---")
        lines.append(debugLogTail(maxLines: 80))

        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    static func saveViaPanel() {
        let report = generate()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "GeorgesWords-diagnostic.txt"
        panel.title = "Save Diagnostic Report"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(report.utf8).write(to: url)
    }

    private static func describe(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "granted"
        case .denied: return "DENIED"
        case .restricted: return "restricted"
        case .notDetermined: return "not asked yet"
        @unknown default: return "unknown"
        }
    }

    private static func describe(_ phase: ManagedOllama.Phase) -> String {
        switch phase {
        case .off: return "off"
        case .downloadingEngine: return "downloading engine"
        case .startingEngine: return "starting"
        case .downloadingModel(let percent):
            return "downloading model (\(percent.map { "\($0)%" } ?? "starting"))"
        case .ready: return "ready"
        case .failed(let message): return "FAILED: \(message)"
        }
    }

    private static func debugLogTail(maxLines: Int) -> String {
        guard let text = try? String(contentsOf: DebugLog.fileURL, encoding: .utf8) else {
            return "(no debug.log yet)"
        }
        return text.split(separator: "\n").suffix(maxLines).joined(separator: "\n")
    }
}

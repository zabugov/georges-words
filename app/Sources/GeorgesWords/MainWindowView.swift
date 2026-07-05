import AppKit
import ApplicationServices
import AVFoundation
import SwiftUI

/// The main app window: sidebar navigation between Home, History,
/// Dictionary, Snippets, and Settings, with the update footer pinned to
/// the bottom of the sidebar and About behind the ? in Home's toolbar.
struct MainWindowView: View {
    @ObservedObject var status = AppStatus.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        NavigationSplitView {
            List(MainSection.sidebarSections, selection: $status.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                UpdateFooter(status: status)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch status.selectedSection ?? .home {
            case .home:
                HomeView(status: status, settings: settings)
            case .history:
                HistoryView(store: HistoryStore.shared)
            case .dictionary:
                DictionaryView(settings: settings)
            case .snippets:
                SnippetsView(settings: settings)
            case .settings:
                SettingsView(settings: settings)
            case .troubleshooting:
                TroubleshootingView(status: status, settings: settings)
            case .about:
                AboutView(status: status, settings: settings)
            }
        }
        .frame(minWidth: 760, minHeight: 500)
    }
}

// MARK: - Home

struct HomeView: View {
    @ObservedObject var status: AppStatus
    @ObservedObject var settings: AppSettings
    @ObservedObject private var stats = StatsStore.shared
    @ObservedObject private var history = HistoryStore.shared
    @State private var copiedEntryID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statCards
                recentDictations
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("George's Words")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    status.selectedSection = .about
                } label: {
                    Label("About", systemImage: "questionmark.circle")
                }
                .help("How to use, privacy, and app info")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("George's Words")
                    .font(.largeTitle.bold())
                HStack(spacing: 6) {
                    Circle()
                        .fill(healthColor)
                        .frame(width: 8, height: 8)
                    Text(status.statusText)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                // Tucked under the status line so it's easy to reference
                // without being a section of its own.
                if let timing = status.lastTiming {
                    Text(timing)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var healthColor: Color {
        switch status.health {
        case .loading: return .orange
        case .ready: return .green
        case .recording: return .red
        case .processing: return .blue
        case .error: return .red
        }
    }

    private var statCards: some View {
        HStack(spacing: 14) {
            StatCard(
                value: StatsStore.formatted(stats.totalWords),
                label: "Words dictated",
                symbol: "text.word.spacing"
            )
            StatCard(
                value: StatsStore.formatted(stats.totalDictations),
                label: "Dictations",
                symbol: "waveform"
            )
            StatCard(
                value: stats.totalWords > 0 ? "~\(stats.timeSavedText)" : "0 min",
                label: "Typing time saved",
                symbol: "clock.arrow.circlepath"
            )
        }
    }

    private func flashCopied(_ id: UUID) {
        copiedEntryID = id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copiedEntryID == id {
                copiedEntryID = nil
            }
        }
    }

    private var recentDictations: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent dictations")
                    .font(.title3.bold())
                Spacer()
                if !history.entries.isEmpty {
                    Button("See all") { status.selectedSection = .history }
                }
            }
            if history.entries.isEmpty {
                Text("Nothing yet — hold \(settings.hotkey.displayName) and speak. Transcripts stay on this Mac.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(history.entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider() }
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.text)
                                    .lineLimit(2)
                                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(entry.text, forType: .string)
                                flashCopied(entry.id)
                            } label: {
                                Image(systemName: copiedEntryID == entry.id ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedEntryID == entry.id ? Color.green : Color.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(copiedEntryID == entry.id ? "Copied" : "Copy")
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

}

// MARK: - Troubleshooting (backlog 6.3): why isn't it working, in one place.

struct TroubleshootingView: View {
    @ObservedObject var status: AppStatus
    @ObservedObject var settings: AppSettings
    @ObservedObject private var managedEngine = ManagedOllama.shared
    @State private var ollamaRunning: Bool?
    @State private var ollamaModels: [String]?
    @State private var recheckTick = 0

    var body: some View {
        Form {
            Section {
                ForEach(healthRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(color(for: row.level))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            if let detail = row.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let fixTitle = row.fixTitle, let fix = row.fix {
                            Button(fixTitle, action: fix)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Button("Recheck") { recheckTick += 1 }
            } header: {
                Text("Health checks")
            }

            Section {
                Text("Dictation degrades gracefully: without Accessibility, transcripts go to the clipboard; without Ollama, you get rule-based cleanup instead of AI polish. Nothing here ever blocks the microphone-to-text path.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Troubleshooting")
        .task(id: recheckTick) {
            ollamaRunning = nil
            ollamaModels = nil
            guard settings.llmEnabled else { return }
            // Re-evaluate the managed engine too: the user's Ollama may
            // have appeared or disappeared since the last look.
            ManagedOllama.shared.ensureReady(model: settings.effectiveLLMModel)
            let running = await LLMFormatter.ollamaIsRunning()
            ollamaRunning = running
            guard running else { return }
            ollamaModels = await LLMFormatter.installedModels()
        }
    }

    private struct HealthRow: Identifiable {
        enum Level {
            case ok, warn, fail
        }
        let id: String
        let level: Level
        let title: String
        let detail: String?
        var fixTitle: String?
        var fix: (() -> Void)?
    }

    private var healthRows: [HealthRow] {
        var rows: [HealthRow] = []

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            rows.append(HealthRow(id: "mic", level: .ok, title: "Microphone", detail: "Permission granted"))
        case .notDetermined:
            rows.append(HealthRow(id: "mic", level: .warn, title: "Microphone", detail: "Not asked yet — starting a dictation triggers the permission prompt"))
        default:
            rows.append(HealthRow(
                id: "mic", level: .fail, title: "Microphone",
                detail: "Permission denied — dictation can't hear you",
                fixTitle: "Open Settings",
                fix: { Self.openPrivacyPane("Privacy_Microphone") }
            ))
        }

        if AXIsProcessTrusted() {
            rows.append(HealthRow(id: "ax", level: .ok, title: "Accessibility", detail: "Permission granted — text can be inserted"))
        } else {
            rows.append(HealthRow(
                id: "ax", level: .fail, title: "Accessibility",
                detail: "Not granted — transcripts go to the clipboard instead of your cursor. After a rebuild, toggle GeorgesWords off and on again in the list.",
                fixTitle: "Open Settings",
                fix: { Self.openPrivacyPane("Privacy_Accessibility") }
            ))
        }

        switch status.health {
        case .error:
            rows.append(HealthRow(id: "model", level: .fail, title: "Speech model", detail: status.statusText))
        case .loading:
            rows.append(HealthRow(id: "model", level: .warn, title: "Speech model", detail: "Downloading / loading — dictation available once this finishes"))
        default:
            rows.append(HealthRow(id: "model", level: .ok, title: "Speech model", detail: status.engineDescription))
        }

        if !settings.llmEnabled {
            rows.append(HealthRow(id: "polish", level: .ok, title: "AI polish", detail: "Off — rule-based cleanup only"))
        } else if let managedRow {
            rows.append(managedRow)
        } else if ollamaRunning == nil {
            rows.append(HealthRow(id: "polish", level: .warn, title: "AI polish", detail: "Checking the polish engine…"))
        } else if ollamaRunning == false {
            rows.append(HealthRow(
                id: "polish", level: .warn, title: "AI polish",
                detail: "The polish engine isn't running — Recheck starts it. Dictation still works meanwhile, with rule-based cleanup.",
                fixTitle: "Recheck",
                fix: { ManagedOllama.shared.ensureReady(model: settings.effectiveLLMModel) }
            ))
        } else if let models = ollamaModels, !models.contains(settings.effectiveLLMModel) {
            rows.append(HealthRow(
                id: "polish", level: .warn, title: "AI polish",
                detail: "\(settings.effectiveLLMModel) isn't downloaded yet — the engine fetches it automatically; Recheck to kick it",
                fixTitle: "Recheck",
                fix: { ManagedOllama.shared.ensureReady(model: settings.effectiveLLMModel) }
            ))
        } else {
            rows.append(HealthRow(id: "polish", level: .ok, title: "AI polish", detail: "\(settings.effectiveLLMModel), ready"))
        }

        return rows
    }

    /// The engine's live state, when it's doing something worth showing.
    /// nil = fall back to the endpoint probes.
    private var managedRow: HealthRow? {
        let model = settings.effectiveLLMModel
        switch managedEngine.phase {
        case .off:
            return nil
        case .downloadingEngine:
            return HealthRow(id: "polish", level: .warn, title: "AI polish", detail: "Downloading the polish engine (~120 MB, one-time)…")
        case .startingEngine:
            return HealthRow(id: "polish", level: .warn, title: "AI polish", detail: "Starting the managed polish engine…")
        case .downloadingModel(let percent):
            let suffix = percent.map { " — \($0)%" } ?? "…"
            return HealthRow(id: "polish", level: .warn, title: "AI polish", detail: "Downloading \(model)\(suffix)")
        case .ready:
            return HealthRow(id: "polish", level: .ok, title: "AI polish", detail: "\(model) via the managed engine, ready")
        case .failed(let message):
            return HealthRow(
                id: "polish", level: .warn, title: "AI polish",
                detail: "Managed engine: \(message) Dictation still works with rule-based cleanup.",
                fixTitle: "Retry",
                fix: { ManagedOllama.shared.ensureReady(model: model) }
            )
        }
    }

    private func color(for level: HealthRow.Level) -> Color {
        switch level {
        case .ok: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }

    private static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Sidebar update footer

/// All update UI lives here, bottom-left of the sidebar: one button that
/// becomes a spinner + live progress while an update runs, plus a short
/// outcome notice and the version number.
private struct UpdateFooter: View {
    @ObservedObject var status: AppStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if let progress = status.updateProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.top, 4)
            } else {
                Button {
                    status.checkForUpdates?()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .padding(.top, 4)
            }
            if let notice = status.updateNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Version \(AboutView.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - About

/// The one place for informational bits: instructions, the privacy
/// promise, engine details, version. Reached via the ? in the sidebar
/// footer — deliberately out of the way of daily use.
struct AboutView: View {
    @ObservedObject var status: AppStatus
    @ObservedObject var settings: AppSettings
    @State private var versionTaps = 0

    var body: some View {
        Form {
            Section("How to dictate") {
                Text("Hold \(settings.hotkey.displayName) in any text field, speak, and release — the polished text is inserted at your cursor.")
                Text("Quick-tap \(settings.hotkey.displayName) to go hands-free: tap once to start, tap again to stop.")
                Text("Press Esc while recording to cancel.")
                Text("Command mode: select text anywhere, hold \(settings.commandHotkey.displayName), and speak an instruction — “make this shorter”, “make it a bulleted list”, “translate to French”. Requires the local LLM (Ollama).")
            }

            Section("Privacy") {
                Label {
                    Text("Audio and transcripts never leave this Mac. Transcription and polish run 100% on-device — no cloud services, no accounts, no telemetry.")
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Engine") {
                Text(status.engineDescription)
                if settings.llmEnabled {
                    Text("Polish model: \(settings.effectiveLLMModel) via the app's built-in engine (localhost)")
                }
                Text("Tip: set System Settings → Keyboard → “Press 🌐 key” to “Do Nothing” so holding Fn doesn’t open the emoji picker.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                // Clicking the version five times reveals the testing-only
                // factory reset — deliberately undiscoverable.
                LabeledContent("Version", value: Self.version)
                    .contentShape(Rectangle())
                    .onTapGesture { versionTaps += 1 }
                Button("Replay Welcome Tour") { status.replayOnboarding?() }
                Link("GitHub repository", destination: URL(string: "https://github.com/zabugov/georges-words")!)
                if versionTaps >= 5 {
                    Button("Erase Everything & Quit", role: .destructive) {
                        FactoryReset.perform()
                    }
                    Text("Fresh-install testing: wipes all settings, history, stats, the downloaded speech/polish files, and revokes the Microphone and Accessibility permissions, then quits. The next launch behaves exactly like a brand-new install — including ~1.6 GB of re-downloads.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }

    static var version: String {
        let marketing = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let commit = Bundle.main.object(forInfoDictionaryKey: "GWBuildCommit") as? String
        let date = Bundle.main.object(forInfoDictionaryKey: "GWBuildDate") as? String
        switch (commit, date) {
        case let (commit?, date?):
            return "\(marketing) — build \(commit), \(date)"
        case let (commit?, nil):
            return "\(marketing) — build \(commit)"
        default:
            // Bundles assembled before stamping existed (or stray copies).
            return "\(marketing) — unstamped build"
        }
    }
}

/// Testing-only: return the app to a factory-fresh state. Wipes defaults
/// (settings, stats, onboarding flag), Application Support (history,
/// corrections, the polish engine + models), revokes the TCC permissions
/// via tccutil, and quits. Next launch = genuine first run.
enum FactoryReset {

    @MainActor
    static func perform() {
        // Stop the polish engine so its files aren't held open.
        ManagedOllama.shared.shutdown()

        let bundleID = Bundle.main.bundleIdentifier ?? "com.georges.words"
        for service in ["Microphone", "Accessibility"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", service, bundleID]
            try? process.run()
            process.waitUntilExit()
        }

        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeorgesWords", isDirectory: true)
        try? FileManager.default.removeItem(at: appSupport)

        NSApp.terminate(nil)
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Dictionary

struct DictionaryView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var status = AppStatus.shared
    @ObservedObject private var corrections = CorrectionStore.shared
    @State private var correctionDraft = ""
    @State private var learnFeedback: String?

    var body: some View {
        Form {
            Section("Suggestions") {
                if corrections.suggestions.isEmpty {
                    Text("When you fix a dictation right after it's inserted (or below), the app notices and suggests dictionary entries here. Nothing is added without your OK.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(corrections.suggestions) { suggestion in
                        HStack(spacing: 6) {
                            Text(suggestion.heard)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(suggestion.corrected)
                            if suggestion.timesSeen > 1 {
                                Text("×\(suggestion.timesSeen)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Add") {
                                corrections.accept(suggestion, into: settings)
                            }
                            Button {
                                corrections.dismiss(suggestion)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.borderless)
                            .help("Dismiss — won't be suggested again")
                        }
                    }
                }
            }

            Section("Personal dictionary") {
                TextEditor(text: $settings.dictionaryText)
                    .font(.body.monospaced())
                    .frame(minHeight: 180)
                Text("One entry per line. A plain term enforces its exact spelling (names, jargon, product words). A “heard -> Correct” line fixes a specific mishearing — accepting a suggestion writes one of these.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Fix the last transcript") {
                if let last = status.lastTranscript {
                    TextEditor(text: $correctionDraft)
                        .font(.body)
                        .frame(minHeight: 70)
                    HStack {
                        Button("Learn Corrections") {
                            let substitutions = CorrectionDetector.substitutions(from: last, to: correctionDraft)
                            for substitution in substitutions {
                                corrections.add(
                                    heard: substitution.heard,
                                    corrected: substitution.corrected,
                                    settings: settings
                                )
                            }
                            learnFeedback = substitutions.isEmpty
                                ? "No learnable word changes found."
                                : "Found \(substitutions.count) — review under Suggestions above."
                        }
                        .disabled(correctionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let learnFeedback {
                            Text(learnFeedback)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Edit the transcript to what it should have said, then Learn Corrections. Useful in apps where automatic detection can't read the text field.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Dictate something first — the transcript will appear here for fixing.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dictionary")
        .onAppear {
            correctionDraft = status.lastTranscript ?? ""
            learnFeedback = nil
        }
    }
}

// MARK: - Snippets

struct SnippetsView: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Voice snippets") {
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
        }
        .formStyle(.grouped)
        .navigationTitle("Snippets")
    }
}

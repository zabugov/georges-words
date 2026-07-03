import AppKit
import SwiftUI

/// The main app window: sidebar navigation between Home, History,
/// Dictionary, Snippets, and Settings.
struct MainWindowView: View {
    @ObservedObject var status = AppStatus.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $status.selectedSection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statCards
                setupCard
                recentDictations
                footer
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle("George's Words")
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

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Hold **\(settings.hotkey.displayName)** in any text field and speak — release to insert. Quick-tap to dictate hands-free.")
            } icon: {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
            }
            Label {
                Text(status.engineDescription)
            } icon: {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
            }
            if let timing = status.lastTiming {
                Label {
                    Text(timing)
                } icon: {
                    Image(systemName: "stopwatch")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
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
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy")
                        }
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let progress = status.updateProgress {
                ProgressView()
                    .controlSize(.small)
                Text(progress)
                    .foregroundStyle(.secondary)
            } else {
                Button("Check for Updates…") { status.checkForUpdates?() }
                Text("Version \(Self.version)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("Audio and transcripts never leave this Mac", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
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

    var body: some View {
        Form {
            Section("Personal dictionary") {
                TextEditor(text: $settings.dictionaryText)
                    .font(.body.monospaced())
                    .frame(minHeight: 260)
                Text("One term per line — names, jargon, product words. Their exact spelling is enforced in every transcript.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dictionary")
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

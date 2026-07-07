import Foundation

/// How long dictation history is kept (backlog 8.2). History only ever
/// lives on this Mac; this controls how long even that copy exists.
enum HistoryRetention: String, CaseIterable, Identifiable {
    case off        // keep nothing at all
    case session    // in memory only — gone when the app quits
    case week       // persisted, pruned after 7 days
    case standard   // persisted, last 200 entries (the original behavior)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Keep nothing"
        case .session: return "Until the app quits"
        case .week: return "For 7 days"
        case .standard: return "Last 200 dictations"
        }
    }
}

/// Recent transcripts, persisted locally (Application Support) so they
/// survive restarts. Capped, clearable, and never synced anywhere.
final class HistoryStore: ObservableObject {

    static let shared = HistoryStore()
    private static let maxEntries = 200
    private static let weekSeconds: TimeInterval = 7 * 24 * 3600

    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let text: String
        let date: Date
    }

    @Published private(set) var entries: [Entry] = []

    private var retention: HistoryRetention
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeorgesWords", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("history.json")

        // Read the setting straight from defaults — going through
        // AppSettings.shared here would tie the two singletons' init order
        // together for no benefit.
        retention = HistoryRetention(rawValue: UserDefaults.standard.string(forKey: "HistoryRetention") ?? "") ?? .standard

        switch retention {
        case .off, .session:
            // Nothing from previous runs may survive.
            try? FileManager.default.removeItem(at: fileURL)
        case .week, .standard:
            if let data = try? Data(contentsOf: fileURL),
               let saved = try? JSONDecoder().decode([Entry].self, from: data) {
                entries = saved
                enforceRetention()
                persist()
            }
        }
    }

    func add(_ text: String) {
        guard retention != .off else { return }
        entries.insert(Entry(id: UUID(), text: text, date: Date()), at: 0)
        enforceRetention()
        persist()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    /// The user changed the retention setting — apply it to what's
    /// already stored, immediately (switching to Off clears everything).
    func apply(_ newRetention: HistoryRetention) {
        retention = newRetention
        if retention == .off { entries = [] }
        enforceRetention()
        persist()
    }

    private func enforceRetention() {
        switch retention {
        case .off:
            entries = []
        case .session:
            break
        case .week:
            let cutoff = Date().addingTimeInterval(-Self.weekSeconds)
            entries.removeAll { $0.date < cutoff }
        case .standard:
            if entries.count > Self.maxEntries {
                entries.removeLast(entries.count - Self.maxEntries)
            }
        }
    }

    private func persist() {
        switch retention {
        case .off, .session:
            // These modes never leave history on disk.
            try? FileManager.default.removeItem(at: fileURL)
        case .week, .standard:
            guard let data = try? JSONEncoder().encode(entries) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

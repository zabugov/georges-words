import Foundation

/// Recent transcripts, persisted locally (Application Support) so they
/// survive restarts. Capped, clearable, and never synced anywhere.
final class HistoryStore: ObservableObject {

    static let shared = HistoryStore()
    private static let maxEntries = 200

    struct Entry: Codable, Identifiable, Equatable {
        let id: UUID
        let text: String
        let date: Date
    }

    @Published private(set) var entries: [Entry] = []

    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeorgesWords", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        fileURL = appSupport.appendingPathComponent("history.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(_ text: String) {
        entries.insert(Entry(id: UUID(), text: text, date: Date()), at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

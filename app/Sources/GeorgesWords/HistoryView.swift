import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var query = ""

    private var filtered: [HistoryStore.Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return store.entries }
        return store.entries.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "waveform",
                    description: Text("Hold your hotkey in any text field and speak — transcripts land here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(filtered) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text)
                            .lineLimit(6)
                            .textSelection(.enabled)
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("· \(entry.text.split(separator: " ").count) words")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy") {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(entry.text, forType: .string)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            Button("Delete", role: .destructive) {
                                store.remove(id: entry.id)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .searchable(text: $query, prompt: "Search transcripts")
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Clear History", role: .destructive) { store.clear() }
                    .disabled(store.entries.isEmpty)
                Spacer()
                Text("Stored only on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.bar)
        }
        .navigationTitle("History")
    }
}

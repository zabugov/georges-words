import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                Text("No dictations yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.text)
                            .lineLimit(4)
                            .textSelection(.enabled)
                        HStack {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
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
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()
            HStack {
                Button("Clear History", role: .destructive) { store.clear() }
                Spacer()
                Text("Stored only on this Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
        }
        .frame(width: 440, height: 480)
    }
}

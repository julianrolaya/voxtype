import SwiftUI
import Cocoa

struct HistoryView: View {
    @ObservedObject var history = TranscriptionHistory.shared
    @State private var searchText = ""
    @State private var copiedID: UUID?

    private var filteredEntries: [TranscriptionEntry] {
        if searchText.isEmpty { return history.entries }
        return history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            if filteredEntries.isEmpty {
                Spacer()
                Text(history.entries.isEmpty ? "No transcriptions yet" : "No results")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            } else {
                List(filteredEntries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.text)
                                .font(.system(size: 13))
                                .lineLimit(3)
                            Text(entry.timestamp, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            history.copyToClipboard(entry.text)
                            copiedID = entry.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                if copiedID == entry.id { copiedID = nil }
                            }
                        } label: {
                            Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedID == entry.id ? .green : .secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }

            Divider()

            HStack {
                Text("\(history.entries.count) transcription\(history.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear All") {
                    history.clear()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(history.entries.isEmpty)
            }
            .padding(10)
        }
        .frame(width: 400, height: 420)
    }
}

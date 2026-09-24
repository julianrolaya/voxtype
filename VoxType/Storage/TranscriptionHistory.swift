import Foundation
import Cocoa

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let timestamp: Date
    let language: String?

    init(text: String, language: String? = nil) {
        self.id = UUID()
        self.text = text
        self.timestamp = Date()
        self.language = language
    }
}

class TranscriptionHistory: ObservableObject {
    static let shared = TranscriptionHistory()

    @Published private(set) var entries: [TranscriptionEntry] = []

    private let maxEntries = 50
    private let storageURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VoxType")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(_ text: String, language: String? = nil) {
        let entry = TranscriptionEntry(text: text, language: language)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([TranscriptionEntry].self, from: data)
        } catch {
            Log.storage.error("Failed to load history: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            Log.storage.error("Failed to save history: \(error.localizedDescription, privacy: .public)")
        }
    }
}

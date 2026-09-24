import Foundation

final class PerfLog {
    static let shared = PerfLog()

    private let queue = DispatchQueue(label: "com.voxtype.perflog")
    private let enabled: Bool
    private var run: [String: Any] = [:]
    private var marks: [String: Double] = [:]

    private var logURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("VoxType/perf.jsonl")
    }

    private init() {
        enabled = UserDefaults.standard.bool(forKey: "perfLoggingEnabled")
    }

    private func now() -> Double { CFAbsoluteTimeGetCurrent() }

    func begin(audioSeconds: Double, language: String, llmEnabled: Bool, isColdStart: Bool) {
        guard enabled else { return }
        queue.async {
            self.marks = ["t0": self.now()]
            self.run = [
                "ts": ISO8601DateFormatter().string(from: Date()),
                "audio_s": audioSeconds,
                "language": language,
                "llm_enabled": llmEnabled,
                "cold_start": isColdStart,
            ]
        }
    }

    func mark(_ name: String) {
        guard enabled else { return }
        queue.async { self.marks[name] = self.now() }
    }

    func set(_ key: String, _ value: Any) {
        guard enabled else { return }
        queue.async { self.run[key] = value }
    }

    func end() {
        guard enabled else { return }
        queue.async {
            guard self.marks["t0"] != nil else { return }
            var rec = self.run

            func ms(_ a: String, _ b: String) -> Double? {
                guard let x = self.marks[a], let y = self.marks[b] else { return nil }
                return (y - x) * 1000
            }

            rec["whisper_ms"] = ms("t1", "t3")
            rec["llm_ms"]     = ms("t4", "t5")
            rec["insert_ms"]  = ms("t5", "t6") ?? ms("t3", "t6")
            rec["total_ms"]   = ms("t0", "t6")

            if let audio = rec["audio_s"] as? Double,
               let w = rec["whisper_ms"] as? Double, w > 0 {
                rec["rtf"] = audio / (w / 1000)
            }

            rec = rec.compactMapValues { $0 }

            guard let data = try? JSONSerialization.data(withJSONObject: rec),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"

            let url = self.logURL
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }

            self.marks = [:]
            self.run = [:]
        }
    }
}

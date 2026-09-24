import Foundation

enum HallucinationFilter {

    private static let phrases: Set<String> = [
        "you", "thank you", "thanks", "thank you for watching",
        "thanks for watching", "thank you so much for watching",
        "bye", "goodbye", "bye bye", "the end",
        "please subscribe", "subscribe to my channel",
        "gracias", "muchas gracias", "gracias por ver",
        "gracias por el video", "gracias por el vídeo",
        "gracias por ver el video", "gracias por ver el vídeo",
        "gracias por su atención", "hasta la próxima",
        "suscríbete", "suscribete", "suscríbete al canal", "suscribite",
        "", ".", "..", "...", "…",
    ]

    private static let markers = ["amara.org", "subtitles by", "subtítulos por",
                                  "subtitulos por", "subtitled by"]

    private static func normalize(_ s: String) -> String {
        let stripped = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?¡¿…,;:\"'“”«»-–— "))
        return stripped.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isHallucinatedSentence(_ s: String) -> Bool {
        let n = normalize(s)
        if phrases.contains(n) { return true }
        return markers.contains { n.contains($0) }
    }

    private static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" || ch == "…" {
                out.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append(current)
        }
        return out
    }

    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isHallucinatedSentence(trimmed) { return nil }

        var parts = sentences(trimmed)

        while let last = parts.last, isHallucinatedSentence(last) {
            parts.removeLast()
        }
        while let first = parts.first, isHallucinatedSentence(first) {
            parts.removeFirst()
        }

        let result = parts.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

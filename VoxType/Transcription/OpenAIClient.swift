import Foundation

struct OpenAIClient {
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    struct Message: Codable {
        let role: String
        let content: String
    }

    struct ChatRequest: Codable {
        let model: String
        let messages: [Message]
        let temperature: Double
    }

    struct ChatResponse: Codable {
        struct Choice: Codable {
            let message: Message
        }
        let choices: [Choice]
    }

    func generate(text: String, systemPrompt: String, model: String, apiKey: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let requestObj = ChatRequest(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: text)
            ],
            temperature: 0.1
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestObj)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "No body"
            Log.transcription.error("OpenAI error response: \(body, privacy: .private)")
            throw NSError(domain: "OpenAIError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "OpenAI HTTP \(httpResponse.statusCode): \(body)"])
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? text
    }

    func checkConnection(apiKey: String) async -> Bool {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

import Foundation

struct OllamaClient {
    private let endpoint = URL(string: "http://localhost:11434/api/generate")!

    struct GenerateRequest: Codable {
        let model: String
        let prompt: String
        let system: String
        let stream: Bool
        let options: Options?

        struct Options: Codable {
            let temperature: Double
        }
    }

    struct GenerateResponse: Codable {
        let response: String
    }

    func generate(text: String, systemPrompt: String, model: String) async throws -> String {
        let requestObj = GenerateRequest(
            model: model,
            prompt: text,
            system: systemPrompt,
            stream: false,
            options: .init(temperature: 0.1)
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestObj)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "No body"
            throw NSError(domain: "OllamaError", code: code, userInfo: [NSLocalizedDescriptionKey: "Ollama HTTP \(code): \(body)"])
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func checkConnection() async -> Bool {
        var request = URLRequest(url: URL(string: "http://localhost:11434/")!)
        request.timeoutInterval = 2
        request.httpMethod = "GET"
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

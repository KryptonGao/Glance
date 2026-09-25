import Foundation
import UIKit

nonisolated struct OpenAICompatibleProvider: AIProvider {
    var baseURL: String
    var apiKey: String
    var modelID: String

    func testConnection() async throws {
        let url = try endpointURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelID,
            "messages": [["role": "user", "content": "Reply with OK."]],
            "max_tokens": 1,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GlanceAIError.invalidResponse(String(localized: "The provider did not return an HTTP response."))
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GlanceAIError.http(http.statusCode, String(body.prefix(300)))
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              !choices.isEmpty else {
            throw GlanceAIError.invalidResponse(
                String(localized: "The provider returned an unexpected chat completion response.")
            )
        }
    }

    func analyze(imageData: Data, prompt: String) async throws -> GlanceAnalysis {
        let message = try await complete(imageData: imageData, prompt: prompt, jsonMode: true)
        let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw GlanceAIError.invalidResponse(String(localized: "The provider returned an empty message."))
        }
        let json = extractJSONObject(from: text)
        guard let data = json.data(using: .utf8) else {
            throw GlanceAIError.decoding(String(localized: "The response was not valid text."))
        }
        do {
            return try JSONDecoder().decode(GlanceAnalysis.self, from: data)
        } catch {
            let snippet = json.prefix(180)
            throw GlanceAIError.decoding(String(snippet))
        }
    }

    func ask(imageData: Data, prompt: String) async throws -> GlanceReply {
        let message = try await complete(imageData: imageData, prompt: prompt, jsonMode: false)
        let reply = GlanceReply.parse(content: message.content, reasoning: message.reasoning)
        guard !reply.text.isEmpty || !reply.reasoning.isEmpty else {
            throw GlanceAIError.invalidResponse(String(localized: "The model returned an empty answer."))
        }
        return reply
    }

    private struct ProviderMessage {
        var content: String
        var reasoning: String
    }

    private func complete(imageData: Data, prompt: String, jsonMode: Bool) async throws -> ProviderMessage {
        try await perform(imageData: imageData, prompt: prompt, jsonMode: jsonMode, allowJSONRetry: jsonMode)
    }

    private func perform(
        imageData: Data,
        prompt: String,
        jsonMode: Bool,
        allowJSONRetry: Bool
    ) async throws -> ProviderMessage {
        let url = try endpointURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload(
            prompt: prompt,
            imageData: imageData,
            jsonMode: jsonMode
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GlanceAIError.invalidResponse(String(localized: "The provider did not return an HTTP response."))
        }

        if allowJSONRetry, http.statusCode == 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            if body.localizedCaseInsensitiveContains("response_format") {
                return try await perform(
                    imageData: imageData,
                    prompt: prompt,
                    jsonMode: false,
                    allowJSONRetry: false
                )
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw GlanceAIError.http(http.statusCode, String(body.prefix(300)))
        }
        return try providerMessage(from: data)
    }

    private func endpointURL() throws -> URL {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else {
            throw GlanceAIError.invalidConfiguration(String(localized: "Enter a valid base URL."))
        }
        if !trimmed.hasSuffix("/chat/completions") {
            trimmed += "/chat/completions"
        }
        guard let url = URL(string: trimmed) else {
            throw GlanceAIError.invalidConfiguration(String(localized: "Enter a valid base URL."))
        }
        return url
    }

    private func payload(prompt: String, imageData: Data, jsonMode: Bool) -> [String: Any] {
        let dataURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        var body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": GlancePrompts.system],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": dataURL]],
                    ],
                ],
            ],
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        return body
    }

    private func providerMessage(from data: Data) throws -> ProviderMessage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw GlanceAIError.invalidResponse(String(localized: "The provider response did not include a message."))
        }
        let content = messageContent(message)
        let reasoning = messageReasoning(message)
        if content.isEmpty && reasoning.isEmpty {
            throw GlanceAIError.invalidResponse(String(localized: "The provider returned an empty message."))
        }
        return ProviderMessage(content: content, reasoning: reasoning)
    }

    private func messageContent(_ message: [String: Any]) -> String {
        if let text = message["content"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = message["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func messageReasoning(_ message: [String: Any]) -> String {
        for key in ["reasoning_content", "reasoning"] {
            if let text = message[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return ""
    }
}

nonisolated func extractJSONObject(from text: String) -> String {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("```") {
        if let newline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: newline)...])
        }
        if let fence = trimmed.range(of: "```", options: .backwards) {
            trimmed = String(trimmed[..<fence.lowerBound])
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    guard let start = trimmed.firstIndex(of: "{"),
          let end = trimmed.lastIndex(of: "}"),
          start <= end else {
        return trimmed
    }
    return String(trimmed[start...end])
}

enum ImageJPEG {
    static func encode(_ image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.72) -> Data? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let longest = max(pixelSize.width, pixelSize.height)
        guard longest > 0 else { return nil }
        let ratio = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: max(pixelSize.width * ratio, 1), height: max(pixelSize.height * ratio, 1))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}

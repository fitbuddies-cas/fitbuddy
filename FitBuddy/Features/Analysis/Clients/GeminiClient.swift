import Foundation

/// Calls the Gemini API's streaming `generateContent` endpoint (#79).
///
/// Uses the Generative Language API (`generativelanguage.googleapis.com`), the
/// product a user's own AI Studio key is issued for — the BYO-key model of
/// ADR-007. Vertex AI, named in ADR-005 as the pre-v1.0 EU-hosting path, needs
/// Google Cloud credentials rather than an API key and is a v1 migration, not
/// a drop-in host swap here.
struct GeminiClient: LLMProviderClient {
    /// Flash tier: the analysis is a sub-200-word paragraph, and this is billed
    /// to the user's own key.
    static let model = "gemini-3.7-flash"
    static let maxOutputTokens = 4096

    private static let host = "https://generativelanguage.googleapis.com/v1beta/models/"

    let provider = LLMProvider.gemini

    private let session: URLSession

    init(session: URLSession = .fitBuddyStreaming) {
        self.session = session
    }

    func streamAnalysis(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let bytes = try await LLMStreamTransport.send(
            try makeRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey),
            on: session
        )
        let payloads = LLMStreamTransport.dataPayloads(of: bytes)
        return AsyncThrowingStream { continuation in
            let task = Task {
                let decoder = JSONDecoder()
                do {
                    for try await payload in payloads {
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(GeminiStreamChunk.self, from: data) else { continue }
                        if let interruption = chunk.interruption {
                            // Gemini can abort after already answering 200 — a
                            // blocked prompt, a safety stop, an error frame.
                            // None of those carry text, so without this the
                            // loop just reaches the end of input and the call
                            // looks like a normal, if empty, success.
                            throw InferenceServiceError.streamInterrupted(message: interruption)
                        }
                        let text = chunk.text
                        if !text.isEmpty { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(systemPrompt: String, userPrompt: String, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(Self.host)\(Self.model):streamGenerateContent?alt=sse") else {
            throw InferenceServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Header, never the `?key=` query parameter Google's examples use: a
        // key in a URL ends up in redirect targets and logs, which is exactly
        // what the Keychain-only rule exists to prevent.
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(
            GeminiGenerateContentRequest(
                systemInstruction: .init(role: nil, parts: [.init(text: systemPrompt)]),
                contents: [.init(role: "user", parts: [.init(text: userPrompt)])],
                generationConfig: .init(
                    maxOutputTokens: Self.maxOutputTokens,
                    responseMimeType: "application/json",
                    responseJsonSchema: AnalysisReportSchema.schema.addingPropertyOrdering()
                )
            )
        )
        return request
    }
}

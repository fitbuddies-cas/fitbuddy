import Foundation

/// Calls the Gemini API's streaming `generateContent` endpoint (#79).
///
/// Uses the Generative Language API (`generativelanguage.googleapis.com`), the
/// product a user's own AI Studio key is issued for — the BYO-key model of
/// ADR-007. Vertex AI, named in ADR-005 as the pre-v1.0 EU-hosting path, needs
/// Google Cloud credentials rather than an API key and is a v1 migration, not
/// a drop-in host swap here.
struct GeminiClient: LLMProviderClient {
    /// Flash tier: the analysis is a short JSON report, and this is billed to
    /// the user's own key.
    ///
    /// `gemini-3.6-flash`, not `gemini-3.7-flash` (#209): for a current AI
    /// Studio key the newer model answered every single call with 503 «high
    /// demand» — ten out of ten over twenty minutes — so no Gemini run ever
    /// completed. 3.6 is the model Google's own error text names as the
    /// replacement for retired ones, and it answers.
    ///
    /// Context window: 1 M tokens. The prompt is sized against the
    /// *smallest* window of the three providers, not this one — see
    /// `AnalysisPromptBudget.smallestContextWindowTokens`, which has to be
    /// revisited if this model is ever swapped for one with a smaller
    /// window than Mistral's.
    static let model = "gemini-3.6-flash"
    /// Room for the report — a sub-200-word summary plus up to four cards —
    /// and the thinking tokens that share this budget. A JSON answer cut off
    /// before its summary is no answer at all (#174).
    static let maxOutputTokens = 8192

    /// How long to wait before the one retry of an overloaded call — see
    /// `streamAnalysis`.
    static let defaultRetryDelay: Duration = .seconds(2)

    private static let host = "https://generativelanguage.googleapis.com/v1beta/models/"

    let provider = LLMProvider.gemini

    private let session: URLSession
    private let retryDelay: Duration

    /// - Parameters:
    ///   - session: Injectable for tests (stub `URLProtocol`).
    ///   - retryDelay: Injectable so tests do not wait out the real pause.
    init(session: URLSession = .fitBuddyStreaming, retryDelay: Duration = GeminiClient.defaultRetryDelay) {
        self.session = session
        self.retryDelay = retryDelay
    }

    func streamAnalysis(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        let request = try makeRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey)
        let bytes = try await sendWithOneRetry(request)
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

    /// Sends the request, and once more after `retryDelay` when Gemini answers
    /// 503 (#209).
    ///
    /// Gemini's flash models shed load with a 503 «high demand» on roughly one
    /// call in four, measured against the same key minutes apart — and the
    /// next call goes through. Nothing has been billed at that point (the 503
    /// arrives before any token), so a second attempt costs the user only the
    /// pause. One retry, not a loop: a model that is down for good still has
    /// to hand over to the next provider within seconds, not minutes.
    private func sendWithOneRetry(_ request: URLRequest) async throws -> URLSession.AsyncBytes {
        do {
            return try await LLMStreamTransport.send(request, on: session)
        } catch InferenceServiceError.serviceUnavailable {
            try await Task.sleep(for: retryDelay)
            return try await LLMStreamTransport.send(request, on: session)
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
                    responseJsonSchema: AnalysisReportSchema.schema
                )
            )
        )
        return request
    }
}

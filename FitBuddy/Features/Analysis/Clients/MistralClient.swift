import Foundation

/// Calls Mistral La Plateforme's streaming chat completions endpoint (#79).
///
/// The only one of the three providers hosted in the EU (Mistral AI SAS,
/// Paris), so a run answered here involves no third-country transfer — see
/// ADR-007.
struct MistralClient: LLMProviderClient {
    /// Mistral Medium 3.5. Pinned rather than `mistral-medium-latest`: the
    /// alias can move to a new version mid-deploy, changing both behaviour and
    /// the price charged to the user's own key.
    static let model = "mistral-medium-2604"
    static let maxTokens = 4096

    /// Terminator of an OpenAI-shaped SSE stream. Not JSON, so it has to be
    /// recognised before the decoder sees it.
    private static let doneSentinel = "[DONE]"
    private static let endpoint = URL(staticString: "https://api.mistral.ai/v1/chat/completions")

    let provider = LLMProvider.mistral

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
            makeRequest(systemPrompt: systemPrompt, userPrompt: userPrompt, apiKey: apiKey),
            on: session
        )
        let payloads = LLMStreamTransport.dataPayloads(of: bytes)
        return AsyncThrowingStream { continuation in
            let task = Task {
                let decoder = JSONDecoder()
                do {
                    for try await payload in payloads {
                        guard payload != Self.doneSentinel else { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(MistralStreamChunk.self, from: data) else { continue }
                        if let interruption = chunk.interruption {
                            // Same post-200 abort as Claude's `error` event and
                            // Gemini's blocked prompt: reported inside the
                            // stream, invisible to the status-code check.
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
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            MistralChatRequest(
                model: Self.model,
                maxTokens: Self.maxTokens,
                stream: true,
                messages: [
                    MistralChatRequest.Message(role: "system", content: systemPrompt),
                    MistralChatRequest.Message(role: "user", content: userPrompt)
                ]
            )
        )
        return request
    }
}

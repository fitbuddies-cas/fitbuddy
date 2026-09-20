import Foundation

/// Calls Mistral La Plateforme's streaming chat completions endpoint (#79).
///
/// The only one of the three providers hosted in the EU (Mistral AI SAS,
/// Paris), so a run answered here involves no third-country transfer — see
/// ADR-007.
struct MistralClient: LLMProviderClient {
    /// Mistral Medium 3.5 (v26.04), under the id Mistral bills it as and
    /// documents it under (#211). Pinned rather than `mistral-medium-latest`:
    /// that alias moves to the next major version, changing both behaviour
    /// and the price charged to the user's own key. The dated
    /// `mistral-medium-2604` this client first shipped with is an alias of
    /// the same release, not a separate snapshot; the docs and the pricing
    /// page never mention it. Whether Mistral can re-point either id to a
    /// revised build of 3.5 is not documented — the two are equal in that
    /// respect, so the documented name wins.
    ///
    /// **Context window: 128 k tokens — the smallest of the three, and so
    /// the one the prompt budget is derived from**
    /// (`AnalysisPromptBudget.smallestContextWindowTokens`, TD-1/#187).
    /// Changing this pin to a model with a different window means changing
    /// that constant with it.
    static let model = "mistral-medium-3-5"
    /// Same budget as the other two: the report is a summary plus up to four
    /// cards, and a JSON answer cut off before its summary is no answer (#174).
    static let maxTokens = 8192
    /// Medium 3.5 is a reasoning model, and the request leaves reasoning at
    /// Mistral's default. `reasoning_effort: "none"` would spare the user's
    /// key the thinking tokens, but Mistral rejects the field with a 400 on
    /// models it is not enabled for, and it could not be verified against
    /// Medium 3.5 yet (#211) — a wrong guess would take Mistral out for every
    /// user. `MistralStreamChunk` drops the thinking chunks either way, so
    /// the answer stays plain without it.

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
                ],
                responseFormat: MistralChatRequest.ResponseFormat(
                    jsonSchema: .init(name: AnalysisReportSchema.name, schema: AnalysisReportSchema.schema, strict: true)
                )
            )
        )
        return request
    }
}

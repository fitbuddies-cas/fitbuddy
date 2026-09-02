import Foundation

/// Calls Claude's streaming Messages API (#29, extracted into a client by #79).
///
/// The original `InferenceService` logic, unchanged in behaviour: `POST
/// /v1/messages` with `x-api-key`, and SSE `content_block_delta` events read
/// for their text.
struct AnthropicClient: LLMProviderClient {
    /// Model used for every analysis call. The recommendation is short prose,
    /// but it is the one place FitBuddy asks a model to reason about a training
    /// history, so the flagship stays.
    static let model = "claude-opus-5"
    /// A training recommendation is a short, focused paragraph, not a
    /// code-generation-scale response — capped well below the model's ceiling
    /// so a malformed prompt cannot run up an unbounded bill on the user's
    /// own key.
    ///
    /// Not the prose budget alone: thinking is on by default on this model and
    /// its tokens count against `max_tokens` too, so a cap sized for the
    /// paragraph only could be spent entirely on reasoning — the response would
    /// end at `max_tokens` having sent nothing but `thinking_delta`s, which the
    /// parser below correctly ignores, and the run would produce no text at all.
    static let maxTokens = 8192
    /// Thinking effort. Low, because the model is being asked for a short
    /// recommendation from a handful of workout summaries, not for a hard
    /// reasoning problem — and because every thinking token is billed to the
    /// user's own key and shares the budget above.
    static let effort = "low"

    private static let endpoint = URL(staticString: "https://api.anthropic.com/v1/messages")
    private static let anthropicVersion = "2023-06-01"

    let provider = LLMProvider.claude

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
                        guard let data = payload.data(using: .utf8),
                              let event = try? decoder.decode(ClaudeStreamEvent.self, from: data) else { continue }
                        switch event.type {
                        case "content_block_delta":
                            if let text = event.delta?.text { continuation.yield(text) }
                        case "error":
                            // Claude can abort a stream after already answering 200
                            // (e.g. an overload mid-generation) — without this, the
                            // loop simply reaches the end of input and the call
                            // looks like a normal, if short, success.
                            throw InferenceServiceError.streamInterrupted(
                                message: event.error?.message ?? "unknown"
                            )
                        default:
                            continue
                        }
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
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        // Idle timeout (NFR: ~30s) comes from the session's
        // `timeoutIntervalForRequest` (`.fitBuddyStreaming`), not a per-request
        // override here — the two do not reliably compose.
        request.httpBody = try JSONEncoder().encode(
            ClaudeMessageRequest(
                model: Self.model,
                maxTokens: Self.maxTokens,
                system: systemPrompt,
                stream: true,
                messages: [ClaudeMessageRequest.Message(role: "user", content: userPrompt)],
                outputConfig: ClaudeMessageRequest.OutputConfig(effort: Self.effort)
            )
        )
        return request
    }
}

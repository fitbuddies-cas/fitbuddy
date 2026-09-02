import Foundation

/// One provider's half of an analysis call: build the request, send it, and
/// hand back the answer as it arrives (#79).
///
/// The seam that lets `InferenceService` be an orchestrator instead of a
/// Claude client. Everything provider-specific — endpoint, auth header, body
/// encoding, stream format — lives behind this protocol; the fallback chain
/// above it only sees "this one worked" or "this one failed".
///
/// **Throwing before returning the stream means the provider never accepted
/// the request** (bad key, offline, 4xx/5xx). An error delivered *through* the
/// stream means it accepted and then failed mid-answer. The orchestrator falls
/// back in both cases, but only the second one has cost the user tokens — which
/// is what decides whether the 6h cooldown is spent.
protocol LLMProviderClient: Sendable {
    /// Which provider this client speaks to, so the orchestrator can label a
    /// run without keeping a parallel mapping.
    var provider: LLMProvider { get }

    /// Streams incremental text chunks for `userPrompt` under `systemPrompt`,
    /// authenticated with `apiKey`.
    ///
    /// - Throws: `InferenceServiceError` when the provider rejected the request
    ///   before answering, and through the returned stream afterwards.
    func streamAnalysis(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error>
}

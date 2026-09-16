import Foundation

/// Streams a training analysis from an LLM, falling back across the user's
/// configured providers (#79).
///
/// `AnalysisViewModel` depends on this protocol rather than on
/// `InferenceService`, so its state machine can be driven through every path —
/// slow first token, mid-stream failure, provider fallback, cancellation —
/// against a double, with no `URLProtocol` stub and no Keychain involved.
protocol AnalysisStreaming: Sendable {
    /// Streams the run for `userPrompt` under `systemPrompt` as a sequence of
    /// `AnalysisEvent`s.
    ///
    /// - Throws: `InferenceServiceError` before the first event (no key,
    ///   already running) and through the stream afterwards — the
    ///   latter only once every configured provider has failed.
    func streamAnalysis(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<AnalysisEvent, Error>
}

extension InferenceService: AnalysisStreaming {}

import Foundation

/// Streams a training analysis from an LLM.
///
/// `AnalysisViewModel` depends on this protocol rather than on
/// `InferenceService`, so its state machine can be driven through every path —
/// slow first token, mid-stream failure, cancellation — against a double,
/// with no `URLProtocol` stub and no Keychain involved.
protocol AnalysisStreaming: Sendable {
    /// Streams incremental text chunks for `userPrompt` under `systemPrompt`.
    ///
    /// - Throws: `InferenceServiceError` before the first chunk (missing key,
    ///   cooldown, offline, non-2xx) and through the stream afterwards.
    func streamAnalysis(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<String, Error>
}

extension InferenceService: AnalysisStreaming {}

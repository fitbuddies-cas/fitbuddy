import Foundation
@testable import FitBuddy

/// Test double for one provider in the fallback chain, so
/// `InferenceServiceTests` can drive ordering, hand-over and "everyone failed"
/// without three stubbed endpoints.
///
/// Distinguishes the two failure shapes the orchestrator treats differently:
/// `startError` means the provider never accepted the request (no tokens
/// billed), `streamError` means it accepted and then died mid-answer.
final class StubProviderClient: LLMProviderClient, @unchecked Sendable {
    let provider: LLMProvider

    /// Thrown instead of returning a stream — the provider rejected the call.
    var startError: Error?
    /// Yielded before the stream ends.
    var chunks: [String]
    /// Thrown through the stream after `chunks` — the provider accepted, then
    /// failed.
    var streamError: Error?

    /// How often this client was asked, so a test can assert a provider was
    /// skipped rather than merely failing quietly.
    private(set) var callCount = 0
    private(set) var receivedAPIKey: String?

    init(
        provider: LLMProvider,
        chunks: [String] = [],
        startError: Error? = nil,
        streamError: Error? = nil
    ) {
        self.provider = provider
        self.chunks = chunks
        self.startError = startError
        self.streamError = streamError
    }

    func streamAnalysis(
        systemPrompt: String,
        userPrompt: String,
        apiKey: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        callCount += 1
        receivedAPIKey = apiKey
        if let startError { throw startError }
        let chunks = chunks
        let streamError = streamError
        return AsyncThrowingStream { continuation in
            for chunk in chunks { continuation.yield(chunk) }
            continuation.finish(throwing: streamError)
        }
    }
}

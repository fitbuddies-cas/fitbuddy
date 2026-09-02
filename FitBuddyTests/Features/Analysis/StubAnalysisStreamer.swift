import Foundation
import XCTest
@testable import FitBuddy

/// Test double for the analysis stream, so `AnalysisViewModel` can be driven
/// through every path — a slow first token, a mid-stream failure, a provider
/// fallback, a cancellation — without a `URLProtocol` stub or a Keychain
/// entry.
///
/// An `actor`, mirroring `InferenceService`: `AnalysisStreaming` is a
/// nonisolated `async` requirement, so its body runs off the main actor while
/// the tests read `callCount` from it.
actor StubAnalysisStreamer: AnalysisStreaming {
    /// Events yielded by a successful stream, in order.
    private var events: [AnalysisEvent] = []
    /// When set, `streamAnalysis` throws instead of returning a stream.
    private var startError: InferenceServiceError?
    /// When set, the stream yields `chunks` and then fails.
    private var streamError: InferenceServiceError?
    /// Holds the call before it returns a stream, until `release()`.
    private var gated = false
    /// Keeps the stream open after its events instead of finishing it, so a
    /// test can observe the screen mid-run rather than only its outcome. The
    /// consumer's cancellation is what ends it.
    private var holdsOpen = false

    private(set) var callCount = 0
    private(set) var systemPrompt: String?
    private(set) var userPrompt: String?

    /// Resumes the gated call once released.
    private var gate: CheckedContinuation<Void, Never>?
    /// Resumes `waitForCall()` once the gated call has arrived.
    private var arrival: CheckedContinuation<Void, Never>?
    private var callArrived = false

    /// Convenience for the common case: one provider that answers.
    func setChunks(_ chunks: [String], from provider: LLMProvider = .claude) {
        events = [.attempting(provider)] + chunks.map(AnalysisEvent.text)
    }

    /// The exact event sequence, for tests about fallback ordering.
    func setEvents(_ events: [AnalysisEvent]) {
        self.events = events
    }

    func setStartError(_ error: InferenceServiceError?) {
        startError = error
    }

    func setStreamError(_ error: InferenceServiceError?) {
        streamError = error
    }

    /// Makes the next call block before returning its stream, so a test can
    /// observe `.loading` and cancel from there.
    func gateCall() {
        gated = true
    }

    /// Leaves the stream open once `events` have been yielded, so the run stays
    /// in whatever state its last event put it in until the test cancels.
    func holdOpenAfterEvents() {
        holdsOpen = true
    }

    func streamAnalysis(systemPrompt: String, userPrompt: String) async throws -> AsyncThrowingStream<AnalysisEvent, Error> {
        callCount += 1
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt

        if gated {
            callArrived = true
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { gate = $0 }
        }

        if let startError { throw startError }

        let events = events
        let streamError = streamError
        let holdsOpen = holdsOpen
        return AsyncThrowingStream { continuation in
            for event in events { continuation.yield(event) }
            guard !holdsOpen else { return }
            continuation.finish(throwing: streamError)
        }
    }

    /// Suspends until the gated call has reached the gate.
    ///
    /// Signalled, not polled: a bounded yield loop can run out of yields before
    /// the call arrives and then hand back control as if it had waited.
    func waitForCall() async {
        guard !callArrived else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Lets the gated call return its stream. Fails loudly rather than
    /// silently doing nothing, which would leave the call suspended forever.
    func release(file: StaticString = #filePath, line: UInt = #line) {
        guard let gate else {
            return XCTFail("No gated analysis call is waiting to be released", file: file, line: line)
        }
        gate.resume()
        self.gate = nil
    }
}

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
    /// When set, the stream yields `events` and then fails.
    private var streamError: InferenceServiceError?
    /// Holds the call before it returns a stream, until `release()`.
    private var gated = false
    /// Keeps the stream open after its events instead of finishing it, so a
    /// test can observe the screen mid-run rather than only its outcome. The
    /// consumer's cancellation is what ends it.
    private var holdsOpen = false
    /// When set, the stream yields only this many events and holds the rest
    /// until `resumeEvents()`, so a test can act between two events.
    private var pauseAfter: Int?
    /// The open stream and the events it still owes while paused.
    private var pausedContinuation: AsyncThrowingStream<AnalysisEvent, Error>.Continuation?
    private var pausedEvents: [AnalysisEvent] = []

    private(set) var callCount = 0
    private(set) var systemPrompt: String?
    private(set) var userPrompt: String?

    /// Resumes the gated call once released.
    private var gate: CheckedContinuation<Void, Never>?
    /// Resumes `waitForCall()` once the gated call has arrived.
    private var arrival: CheckedContinuation<Void, Never>?
    private var callArrived = false

    /// Convenience for the common case: one provider that answers in prose,
    /// in one piece like `InferenceService` (#174, #178).
    func setText(_ text: String, from provider: LLMProvider = .claude) {
        events = [.attempting(provider), .text(text)]
    }

    /// One provider that answers with a structured report (#178).
    func setReport(_ report: AnalysisReport, from provider: LLMProvider = .claude) {
        events = [.attempting(provider), .report(report)]
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
    /// observe `.running` and cancel from there.
    func gateCall() {
        gated = true
    }

    /// Leaves the stream open once `events` have been yielded, so the run stays
    /// in whatever state its last event put it in until the test cancels.
    func holdOpenAfterEvents() {
        holdsOpen = true
    }

    /// Makes the next stream stop after its first `count` events until
    /// `resumeEvents()`.
    func pauseAfterEvents(_ count: Int) {
        pauseAfter = count
    }

    /// Yields the events held back by `pauseAfterEvents(_:)`, then ends the
    /// stream as an unpaused one would.
    func resumeEvents(file: StaticString = #filePath, line: UInt = #line) {
        guard let continuation = pausedContinuation else {
            return XCTFail("No paused analysis stream is waiting to be resumed", file: file, line: line)
        }
        pausedContinuation = nil
        for event in pausedEvents { continuation.yield(event) }
        pausedEvents = []
        guard !holdsOpen else { return }
        continuation.finish(throwing: streamError)
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

        let (stream, continuation) = AsyncThrowingStream<AnalysisEvent, Error>.makeStream()
        if let pauseAfter {
            for event in events.prefix(pauseAfter) { continuation.yield(event) }
            pausedEvents = Array(events.dropFirst(pauseAfter))
            pausedContinuation = continuation
            return stream
        }
        for event in events { continuation.yield(event) }
        guard !holdsOpen else { return stream }
        continuation.finish(throwing: streamError)
        return stream
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

import XCTest
@testable import FitBuddy

/// Unit tests for `InferenceService` as the fallback orchestrator (#79).
///
/// Drives `StubProviderClient`s rather than stubbed endpoints: what is under
/// test here is *who gets asked, in what order, and what the run costs* — the
/// wire format of each provider belongs to its own client's tests. Keychain
/// access uses the real `KeychainService` on the simulator; the rate limit
/// timestamp lives in an isolated `UserDefaults` suite.
final class InferenceServiceTests: XCTestCase {
    /// Fixed clock so the rate-limit math is deterministic.
    private static let now = Date(timeIntervalSince1970: 1_788_000_000)

    private var keychain: KeychainService!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var rateLimit: AnalysisRateLimitStore!
    private var claude: StubProviderClient!
    private var gemini: StubProviderClient!
    private var mistral: StubProviderClient!
    private var sut: InferenceService!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        for provider in LLMProvider.allCases {
            try await keychain.delete(provider.keychainKey)
        }
        try await keychain.save("sk-ant-test", for: .claudeAPIKey)
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        rateLimit = AnalysisRateLimitStore(defaults: defaults)
        claude = StubProviderClient(provider: .claude, chunks: ["Claude answer"])
        gemini = StubProviderClient(provider: .gemini, chunks: ["Gemini answer"])
        mistral = StubProviderClient(provider: .mistral, chunks: ["Mistral answer"])
        sut = makeService()
    }

    override func tearDown() async throws {
        for provider in LLMProvider.allCases {
            try await keychain.delete(provider.keychainKey)
        }
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        claude = nil
        gemini = nil
        mistral = nil
        rateLimit = nil
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    /// - Parameter priority: Provider order to resolve keys from. Empty (the
    ///   default) is the pre-multi-provider install: a Claude key and no stored
    ///   order.
    private func makeService(priority: [LLMProvider] = []) -> InferenceService {
        let store = LLMPriorityStore(defaults: defaults)
        if !priority.isEmpty {
            defaults.set(priority.map(\.rawValue), forKey: LLMPriorityStore.priorityOrderKey)
        }
        return InferenceService(
            keychain: keychain,
            priority: store,
            rateLimit: rateLimit,
            clients: [.claude: claude, .gemini: gemini, .mistral: mistral],
            now: { Self.now }
        )
    }

    // MARK: - Helpers

    private func collect(_ stream: AsyncThrowingStream<AnalysisEvent, Error>) async throws -> [AnalysisEvent] {
        var events: [AnalysisEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private func run(_ service: InferenceService? = nil) async throws -> [AnalysisEvent] {
        let service = service ?? sut!
        return try await collect(try await service.streamAnalysis(systemPrompt: "s", userPrompt: "u"))
    }

    /// Text of a run, with the `attempting` bookkeeping dropped.
    private func text(of events: [AnalysisEvent]) -> String {
        events.reduce(into: "") { result, event in
            if case .text(let chunk) = event { result += chunk }
        }
    }

    /// Providers announced by a run, in order.
    private func attempted(in events: [AnalysisEvent]) -> [LLMProvider] {
        events.compactMap { event in
            guard case .attempting(let provider) = event else { return nil }
            return provider
        }
    }

    // MARK: - Streaming (AC: Streaming-Output erscheint inkrementell)

    func testStreamsIncrementalTextAfterAnnouncingTheProvider() async throws {
        claude.chunks = ["Increase ", "squat ", "by 2.5 kg."]

        let events = try await run()

        XCTAssertEqual(events, [
            .attempting(.claude),
            .text("Increase "),
            .text("squat "),
            .text("by 2.5 kg.")
        ])
    }

    func testPassesThePromptsAndTheStoredKeyToTheClient() async throws {
        _ = try await run()

        XCTAssertEqual(claude.callCount, 1)
        XCTAssertEqual(claude.receivedAPIKey, "sk-ant-test")
    }

    // MARK: - Priority order (US-4 step 3)

    func testAsksTheHighestPriorityProviderFirst() async throws {
        try await keychain.save("AIza-first", for: .geminiAPIKey)
        sut = makeService(priority: [.gemini, .claude])

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.gemini])
        XCTAssertEqual(text(of: events), "Gemini answer")
        XCTAssertEqual(claude.callCount, 0, "a provider after the answering one must not be called")
        XCTAssertEqual(gemini.receivedAPIKey, "AIza-first")
    }

    func testSkipsAProviderWithNoStoredKeyWithoutCountingItAsAFailure() async throws {
        // Gemini ranks first but was never given a key: it was not configured,
        // so it is not part of the chain at all.
        sut = makeService(priority: [.gemini, .claude])

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.claude])
        XCTAssertEqual(gemini.callCount, 0)
    }

    func testFallsBackToClaudeWhenNoOrderIsStored() async throws {
        // Pre-#78 install: one Claude key, no persisted priority order.
        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.claude])
    }

    func testUsesAStoredKeyThatThePriorityOrderDoesNotName() async throws {
        // The Keychain outlives `UserDefaults`: after a reinstall the keys are
        // still there while the order is gone. The stored key must still be
        // used instead of the run failing as "no API key".
        try await keychain.delete(.claudeAPIKey)
        try await keychain.save("mistral-key", for: .mistralAPIKey)

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.mistral])
        XCTAssertEqual(text(of: events), "Mistral answer")
    }

    func testAppendsAnUnlistedProviderBehindTheStoredOrder() async throws {
        // A partially written order must not hide a key either — but it also
        // must not outrank the providers the user did put in order.
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.startError = InferenceServiceError.unauthorized
        sut = makeService(priority: [.claude])

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.claude, .gemini])
    }

    // MARK: - Fallback chain (DoD: fällt ein Provider aus, übernimmt der nächste)

    func testFallsBackToTheNextProviderWhenTheFirstIsRejected() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.startError = InferenceServiceError.unauthorized
        sut = makeService(priority: [.claude, .gemini])

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.claude, .gemini])
        XCTAssertEqual(text(of: events), "Gemini answer")
    }

    func testFallsBackThroughAllThreeProvidersInOrder() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        try await keychain.save("mistral-key", for: .mistralAPIKey)
        claude.startError = InferenceServiceError.serviceUnavailable
        gemini.startError = InferenceServiceError.rateLimited(retryAfter: 30)
        sut = makeService(priority: [.claude, .gemini, .mistral])

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.claude, .gemini, .mistral])
        XCTAssertEqual(text(of: events), "Mistral answer")
    }

    /// A provider that answered 200 and then died mid-stream is still a failure
    /// the chain has to route around — not an error the user has to see.
    func testFallsBackWhenAProviderFailsAfterItAlreadyStartedAnswering() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.chunks = ["Half an ans"]
        claude.streamError = InferenceServiceError.streamInterrupted(message: "Overloaded")
        sut = makeService(priority: [.claude, .gemini])

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.claude, .gemini])
    }

    /// The partial text of a failed provider still reaches the consumer, but
    /// only ahead of the `attempting` that tells it to throw the text away —
    /// so the two answers can never be shown merged.
    func testPartialOutputOfAFailedProviderIsFollowedByTheNextAttempt() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.chunks = ["Half an ans"]
        claude.streamError = InferenceServiceError.streamInterrupted(message: "Overloaded")
        sut = makeService(priority: [.claude, .gemini])

        let events = try await run()

        XCTAssertEqual(events, [
            .attempting(.claude),
            .text("Half an ans"),
            .attempting(.gemini),
            .text("Gemini answer")
        ])
    }

    /// A provider can answer 200 and then say nothing — a thinking pass that
    /// ate the whole token budget, or an error frame its client does not
    /// recognise. That is not an answer, so the chain must keep going instead
    /// of ending the run with an empty result.
    func testFallsBackWhenAProviderAcceptsButProducesNoText() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.chunks = []
        sut = makeService(priority: [.claude, .gemini])

        let events = try await run()

        XCTAssertEqual(attempted(in: events), [.claude, .gemini])
        XCTAssertEqual(text(of: events), "Gemini answer")
    }

    func testRaisesInvalidResponseWhenEveryProviderAnswersWithoutText() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.chunks = []
        gemini.chunks = []
        sut = makeService(priority: [.claude, .gemini])

        do {
            _ = try await run()
            XCTFail("expected invalidResponse")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .invalidResponse)
        }
    }

    func testRaisesTheLastProvidersErrorWhenAllOfThemFail() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.startError = InferenceServiceError.unauthorized
        gemini.startError = InferenceServiceError.serviceUnavailable
        sut = makeService(priority: [.claude, .gemini])

        do {
            _ = try await run()
            XCTFail("expected serviceUnavailable")
        } catch let error as InferenceServiceError {
            // The last provider's error, not the first: that is the state the
            // user is actually left in.
            XCTAssertEqual(error, .serviceUnavailable)
        }
    }

    // MARK: - No usable key

    func testThrowsMissingAPIKeyBeforeCallingAnyProvider() async throws {
        try await keychain.delete(.claudeAPIKey)

        do {
            _ = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
            XCTFail("expected missingAPIKey")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .missingAPIKey)
        }
        XCTAssertEqual(claude.callCount, 0, "a missing key must not reach a provider")
    }

    func testThrowsMissingAPIKeyWhenNoConfiguredProviderHasAKey() async throws {
        try await keychain.delete(.claudeAPIKey)
        sut = makeService(priority: [.gemini, .mistral])

        do {
            _ = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
            XCTFail("expected missingAPIKey")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .missingAPIKey)
        }
    }

    // MARK: - Rate limit (#117: 60s Doppeltipp-Sperre)

    func testThrowsCooldownActiveWhenCalledTooSoon() async throws {
        let lastCall = Self.now.addingTimeInterval(-30)
        await rateLimit.recordCall(at: lastCall)

        do {
            _ = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
            XCTFail("expected cooldownActive")
        } catch let error as InferenceServiceError {
            guard case .cooldownActive(let availableAt) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(availableAt, lastCall.addingTimeInterval(AnalysisRateLimitStore.duration))
        }
        XCTAssertEqual(claude.callCount, 0, "an active lock must not reach a provider")
    }

    func testSucceedsOnceTheLockHasLifted() async throws {
        await rateLimit.recordCall(at: Self.now.addingTimeInterval(-AnalysisRateLimitStore.duration - 1))

        let events = try await run()

        XCTAssertEqual(text(of: events), "Claude answer")
    }

    func testRecordsTheCallAfterASuccessfulRun() async throws {
        _ = try await run()

        let lastCall = await rateLimit.lastCall()
        XCTAssertEqual(lastCall, Self.now)
    }

    /// DoD: the 6h window is spent once per analysis, not once per provider —
    /// a run that fell back twice must not cost the user three windows.
    ///
    /// Counted through the clock rather than by instrumenting the store: with a
    /// clock that advances on every reading, the recorded timestamp says how
    /// many times it was read, and therefore how many times it was written. A
    /// fixed clock cannot tell one write from three.
    func testRecordsTheCallOnlyOnceAcrossAFallbackChain() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        try await keychain.save("mistral-key", for: .mistralAPIKey)
        // All three accept and then die mid-answer, so every one of them
        // reaches the point where the lock would be started.
        claude.streamError = InferenceServiceError.streamInterrupted(message: "boom")
        gemini.streamError = InferenceServiceError.streamInterrupted(message: "boom")
        mistral.streamError = InferenceServiceError.streamInterrupted(message: "boom")
        let clock = TickingClock(start: Self.now)
        sut = InferenceService(
            keychain: keychain,
            priority: LLMPriorityStore(defaults: defaults),
            rateLimit: rateLimit,
            clients: [.claude: claude, .gemini: gemini, .mistral: mistral],
            now: clock.next
        )
        defaults.set([LLMProvider.claude, .gemini, .mistral].map(\.rawValue), forKey: LLMPriorityStore.priorityOrderKey)

        _ = try? await run()

        // Tick 0 is the pre-flight lock check, tick 1 the single write. A
        // per-provider write would have left tick 3 behind.
        let lastCall = await rateLimit.lastCall()
        XCTAssertEqual(lastCall, Self.now.addingTimeInterval(1),
                       "one analysis must start exactly one lock")
    }

    /// A clock that advances one second per reading, so a test can tell how
    /// many times the code under test asked what time it is.
    private final class TickingClock: @unchecked Sendable {
        private let start: Date
        private let lock = NSLock()
        private var tick = 0

        init(start: Date) {
            self.start = start
        }

        func next() -> Date {
            lock.lock()
            defer { lock.unlock() }
            defer { tick += 1 }
            return start.addingTimeInterval(TimeInterval(tick))
        }
    }

    func testDoesNotRecordTheCallWhenEveryProviderRejectsTheRequest() async throws {
        try await keychain.save("AIza", for: .geminiAPIKey)
        claude.startError = InferenceServiceError.unauthorized
        gemini.startError = InferenceServiceError.unauthorized
        sut = makeService(priority: [.claude, .gemini])

        _ = try? await run()

        let lastCall = await rateLimit.lastCall()
        XCTAssertNil(lastCall, "a request nobody accepted must not start the lock")
    }

    // MARK: - No double-submit (AC: kein zweiter Call möglich während laufendem Call)

    func testRejectsAConcurrentCallWhileOneIsRunning() async throws {
        let stream = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")

        do {
            _ = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
            XCTFail("expected alreadyInProgress")
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .alreadyInProgress)
        }

        // Drain so the first call's internal task does not outlive the test.
        _ = try? await collect(stream)
    }

    /// Regression: `isRunning` must be claimed before the first `await` inside
    /// `streamAnalysis`, not after the rate-limit/Keychain checks — otherwise two
    /// truly concurrent callers both observe the actor as idle before either
    /// sets the flag. `async let` starts both calls together, unlike a
    /// sequential `await` pair which can never exercise this race.
    func testRejectsATrulyConcurrentSecondCallStartedBeforeTheFirstAwaits() async throws {
        async let first = sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
        async let second = sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")

        var successes = 0
        var survivor: AsyncThrowingStream<AnalysisEvent, Error>?
        do {
            survivor = try await first
            successes += 1
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .alreadyInProgress)
        }
        do {
            let stream = try await second
            successes += 1
            survivor = stream
        } catch let error as InferenceServiceError {
            XCTAssertEqual(error, .alreadyInProgress)
        }

        XCTAssertEqual(successes, 1, "exactly one of two truly concurrent calls must win")
        if let survivor {
            _ = try? await collect(survivor)
        }
    }

    func testAllowsANewCallAfterThePreviousOneFinished() async throws {
        claude.chunks = ["First"]
        _ = try await run()
        // Isolates the `isRunning` reset from the (separately tested) lock:
        // the fixed clock would otherwise make this second call look like it
        // arrived seconds after the first, well inside the 6h window.
        await rateLimit.clear()

        claude.chunks = ["Second"]
        let events = try await run()

        XCTAssertEqual(text(of: events), "Second")
    }

    func testAllowsANewCallAfterTheConsumerCancelledThePreviousOne() async throws {
        claude.chunks = Array(repeating: "chunk ", count: 20)
        let stream = try await sut.streamAnalysis(systemPrompt: "s", userPrompt: "u")
        let consumer = Task {
            for try await _ in stream {}
        }
        consumer.cancel()
        _ = try? await consumer.value

        // The actor clears `isRunning` from within its own internal task, which
        // races the assertion below without this: poll rather than guess a
        // fixed delay.
        await waitUntilIdle()
        await rateLimit.clear()

        claude.chunks = ["ok"]
        let events = try await run()
        XCTAssertEqual(text(of: events), "ok")
    }

    /// A bounded poll on `isRunning` (`private(set)`, readable from tests in
    /// the same module) instead of a fixed sleep — avoids both a flake on a
    /// loaded CI and an arbitrarily long wait on a fast one.
    private func waitUntilIdle(timeout: TimeInterval = 1) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await sut.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}

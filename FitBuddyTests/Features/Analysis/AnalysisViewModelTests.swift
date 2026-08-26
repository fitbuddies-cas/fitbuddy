import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisViewModel` (#31): the state machine, the cancel
/// path, and the 6h cooldown label. No network and no Keychain — the stream
/// comes from `StubAnalysisStreamer`, the cooldown from an isolated
/// `UserDefaults` suite.
@MainActor
final class AnalysisViewModelTests: XCTestCase {
    /// Fixed reference point, so both analysis windows are deterministic.
    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    private var cache: StubWorkoutCache!
    private var streamer: StubAnalysisStreamer!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var cooldown: AnalysisCooldownStore!
    private var feedbackStore: AnalysisFeedbackStore!

    override func setUp() async throws {
        try await super.setUp()
        cache = StubWorkoutCache()
        cache.summaries = [Self.workout(daysAgo: 2), Self.workout(daysAgo: 5)]
        streamer = StubAnalysisStreamer()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        cooldown = AnalysisCooldownStore(defaults: defaults)
        feedbackStore = AnalysisFeedbackStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        cooldown = nil
        feedbackStore = nil
        defaults = nil
        streamer = nil
        cache = nil
        try await super.tearDown()
    }

    /// The clock is passed in rather than held in a property, so no test has to
    /// force-unwrap it. Tests that move time keep their own reference.
    private func makeSUT(
        clock: TestClock = TestClock(AnalysisViewModelTests.reference),
        slowThreshold: TimeInterval = 30,
        tickInterval: TimeInterval = 60
    ) -> AnalysisViewModel {
        AnalysisViewModel(
            cache: cache,
            inference: streamer,
            cooldown: cooldown,
            feedbackStore: feedbackStore,
            calendar: Self.calendar,
            now: { clock.date },
            slowThreshold: slowThreshold,
            tickInterval: tickInterval
        )
    }

    /// Fixed time zone, so the window boundaries do not move with the machine
    /// running the tests.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private static func workout(daysAgo: Int, title: String = "Push Day") -> WorkoutSummary {
        WorkoutSummary(
            id: "w-\(daysAgo)",
            title: title,
            startTime: reference.addingTimeInterval(-Double(daysAgo) * 86_400),
            volumeKg: 4_200,
            exerciseCount: 5,
            countedSetCount: 18
        )
    }

    // MARK: - Happy path

    func testSuccessfulRunEndsInResult() async {
        await streamer.setChunks(["Your bench ", "volume is rising."])
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .result("Your bench volume is rising."))
        XCTAssertFalse(sut.isTakingLong)
        XCTAssertNil(sut.cooldownMessage)
    }

    func testStateCarriesTheTextInStreamingAndResult() {
        XCTAssertEqual(AnalysisState.streaming("half").text, "half")
        XCTAssertEqual(AnalysisState.result("whole").text, "whole")
        XCTAssertNil(AnalysisState.loading.text)
        XCTAssertNil(AnalysisState.idle.text)
        XCTAssertNil(AnalysisState.error(.offline).text)
        XCTAssertTrue(AnalysisState.streaming("half").isRunning)
        XCTAssertTrue(AnalysisState.loading.isRunning)
        XCTAssertFalse(AnalysisState.result("whole").isRunning)
    }

    func testRunSendsThePromptBuiltFromTheCachedWindow() async {
        await streamer.setChunks(["ok"])
        let sut = makeSUT()

        await sut.start()

        let system = await streamer.systemPrompt
        let user = await streamer.userPrompt
        XCTAssertEqual(system, AnalysisPromptBuilder.systemPrompt)
        XCTAssertEqual(user?.contains("Push Day"), true)
        // Both windows are read in one go, so the prompt can compare them.
        XCTAssertEqual(
            cache.requestedSince,
            AnalysisWindow.previousStart(endingAt: Self.reference, calendar: Self.calendar)
        )
    }

    /// The state has to pass through `.loading` before any text arrives — that
    /// is the spinner phase of US-3 AC1.
    func testStateIsLoadingBeforeTheFirstToken() async {
        await streamer.gateCall()
        await streamer.setChunks(["done"])
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        XCTAssertEqual(sut.state, .loading)

        await streamer.release()
        await run.value
        XCTAssertEqual(sut.state, .result("done"))
    }

    // MARK: - Guards

    func testEmptyRecentWindowFailsWithoutCallingClaude() async {
        cache.summaries = [Self.workout(daysAgo: 40)]
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.noTrainingData))
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    func testCacheFailureIsReportedAsCacheUnavailable() async {
        cache.error = StubWorkoutCache.Failure()
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.cacheUnavailable))
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    func testActiveCooldownBlocksTheRun() async {
        await cooldown.recordCall(at: Self.reference.addingTimeInterval(-3_600))
        let sut = makeSUT()

        await sut.start()

        let availableAt = Self.reference.addingTimeInterval(AnalysisCooldownStore.duration - 3_600)
        XCTAssertEqual(sut.state, .error(.cooldownActive(availableAt: availableAt)))
        XCTAssertEqual(sut.cooldownMessage, "Next analysis available in 5h 0m")
        XCTAssertFalse(sut.canStartAnalysis)
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    /// A double tap must not buy two analyses.
    func testSecondStartWhileRunningIsIgnored() async {
        await streamer.gateCall()
        await streamer.setChunks(["done"])
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        await sut.start()

        await streamer.release()
        await run.value
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 1)
    }

    /// Both taps land before the first run has passed its first await, where
    /// the state is still `.idle` unless the slot is claimed synchronously.
    func testTwoTapsInTheSameRunLoopStartOnlyOneRun() async {
        await streamer.setChunks(["done"])
        let sut = makeSUT()

        async let first: Void = sut.start()
        async let second: Void = sut.start()
        _ = await (first, second)

        let calls = await streamer.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(sut.state, .result("done"))
    }

    /// A cancel during the cooldown lookup must not be overrun by the run it
    /// stopped before it reached the service.
    func testCancelBeforeTheCallReachesTheServiceStopsTheRun() async {
        await streamer.setChunks(["never rendered"])
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await Task.yield()
        sut.cancel()
        await run.value

        XCTAssertEqual(sut.state, .idle)
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    /// The explanation must not outlive its reason: once the 6h window closes,
    /// the cooldown error clears on the next refresh.
    func testCooldownErrorClearsOnceTheWindowCloses() async {
        let clock = TestClock(Self.reference)
        await cooldown.recordCall(at: Self.reference.addingTimeInterval(-AnalysisCooldownStore.duration + 60))
        let sut = makeSUT(clock: clock)

        await sut.start()
        XCTAssertEqual(sut.state, .error(.cooldownActive(availableAt: Self.reference.addingTimeInterval(60))))

        clock.advance(by: 61)
        await sut.refreshCooldown()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.cooldownMessage)
        XCTAssertTrue(sut.canStartAnalysis)
    }

    // MARK: - Failures

    func testStartFailureIsMappedOntoTheScreen() async {
        await streamer.setStartError(InferenceServiceError.missingAPIKey)
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.missingAPIKey))
    }

    /// A stream that dies half-way is a failure, not a short recommendation.
    func testMidStreamFailureReplacesThePartialText() async {
        await streamer.setChunks(["Your training "])
        await streamer.setStreamError(InferenceServiceError.streamInterrupted(message: "overloaded"))
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.serviceUnavailable))
    }

    func testStreamWithoutAnyTokenIsAnUnreadableResponse() async {
        await streamer.setChunks([])
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.unreadableResponse))
    }

    /// No path may leave the button disabled forever (#31 AC1).
    func testEveryTerminalStateAllowsAnotherRun() async {
        await streamer.setStartError(InferenceServiceError.networkUnavailable)
        let sut = makeSUT()

        await sut.start()

        XCTAssertFalse(sut.state.isRunning)
        XCTAssertTrue(sut.canStartAnalysis)
    }

    // MARK: - Cancel

    func testCancelStopsTheRunAndReturnsToIdle() async {
        await streamer.gateCall()
        await streamer.setChunks(["never rendered"])
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        sut.cancel()
        XCTAssertEqual(sut.state, .idle)

        await streamer.release()
        await run.value

        // The late stream must not resurrect the cancelled run.
        XCTAssertEqual(sut.state, .idle)
        XCTAssertFalse(sut.isTakingLong)
    }

    func testCancelWithoutARunningCallDoesNothing() async {
        await streamer.setChunks(["done"])
        let sut = makeSUT()
        await sut.start()

        sut.cancel()

        XCTAssertEqual(sut.state, .result("done"))
    }

    func testResetClearsAFinishedRun() async {
        await streamer.setChunks(["done"])
        let sut = makeSUT()
        await sut.start()

        sut.reset()

        XCTAssertEqual(sut.state, .idle)
    }

    /// Tearing down the view's `.task` cancels the run from outside, without
    /// going through `cancel()` — the screen must still come to rest.
    func testExternalCancellationLeavesNoStuckState() async {
        await streamer.gateCall()
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        run.cancel()
        await streamer.release()
        await run.value

        XCTAssertFalse(sut.state.isRunning)
        XCTAssertEqual(sut.state, .idle)
    }

    // MARK: - Slow-run hint (US-3 AC1)

    func testSlowRunAnnouncesItselfAfterTheThreshold() async {
        await streamer.gateCall()
        let sut = makeSUT(slowThreshold: 0.05)

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        await waitUntil("the slow hint appears") { sut.isTakingLong }

        sut.cancel()
        await streamer.release()
        await run.value
        XCTAssertFalse(sut.isTakingLong)
    }

    func testFastRunNeverAnnouncesItselfAsSlow() async {
        await streamer.setChunks(["done"])
        let sut = makeSUT(slowThreshold: 60)

        await sut.start()

        XCTAssertFalse(sut.isTakingLong)
    }

    // MARK: - Cooldown label (#31 AC3)

    func testCooldownLabelCountsDownWithTheClock() async {
        await cooldown.recordCall(at: Self.reference.addingTimeInterval(-AnalysisCooldownStore.duration + 130))
        let clock = TestClock(Self.reference)
        let sut = makeSUT(clock: clock, tickInterval: 0.01)

        let ticker = Task { await sut.trackCooldown() }
        await waitUntil("the initial label appears") {
            sut.cooldownMessage == "Next analysis available in 3m"
        }

        clock.advance(by: 120)
        await waitUntil("the label counts down") {
            sut.cooldownMessage == "Next analysis available in 1m"
        }

        clock.advance(by: 60)
        await waitUntil("the label disappears once the window closes") {
            sut.cooldownMessage == nil
        }
        XCTAssertTrue(sut.canStartAnalysis)

        ticker.cancel()
    }

    /// `InferenceService` starts the window mid-call, so the label has to be
    /// re-read when the run ends — not only when the screen is next opened.
    func testCooldownLabelIsRefreshedAfterARun() async {
        await streamer.gateCall()
        await streamer.setChunks(["done"])
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        // Stands in for the service recording the window once Claude accepted
        // the request — after the run's own cooldown check has passed.
        await cooldown.recordCall(at: Self.reference)
        await streamer.release()
        await run.value

        XCTAssertEqual(sut.state, .result("done"))
        XCTAssertEqual(sut.cooldownMessage, "Next analysis available in 6h 0m")
        XCTAssertFalse(sut.canStartAnalysis)
    }

    // MARK: - Feedback (US-3 AC9)

    func testFeedbackOnAResultIsPublishedAndStored() async {
        await streamer.setChunks(["done"])
        let sut = makeSUT()
        await sut.start()

        await sut.submitFeedback(.helpful)

        XCTAssertEqual(sut.feedback, .helpful)
        let stored = await feedbackStore.lastFeedback()
        XCTAssertEqual(stored?.feedback, .helpful)
        XCTAssertEqual(stored?.date, Self.reference)
    }

    /// A tap must not reach the network — US-3 AC9 is "stored locally, no
    /// backend call", and the stub is the only call path there is.
    func testFeedbackDoesNotCallClaude() async {
        await streamer.setChunks(["done"])
        let sut = makeSUT()
        await sut.start()

        await sut.submitFeedback(.notHelpful)

        let calls = await streamer.callCount
        XCTAssertEqual(calls, 1)
    }

    func testFeedbackIsIgnoredWithoutAResultOnScreen() async {
        let sut = makeSUT()

        await sut.submitFeedback(.helpful)

        XCTAssertNil(sut.feedback)
        let stored = await feedbackStore.lastFeedback()
        XCTAssertNil(stored)
    }

    /// A verdict belongs to the recommendation it was given for, so the next
    /// run starts unrated.
    func testANewRunClearsTheVerdict() async {
        await streamer.setChunks(["first"])
        let clock = TestClock(Self.reference)
        let sut = makeSUT(clock: clock)
        await sut.start()
        await sut.submitFeedback(.helpful)

        clock.advance(by: AnalysisCooldownStore.duration + 1)
        await streamer.setChunks(["second"])
        await sut.start()

        XCTAssertEqual(sut.state, .result("second"))
        XCTAssertNil(sut.feedback)
    }

    // MARK: - Helpers

    /// Polls `condition` until it holds, failing the test on timeout instead of
    /// hanging it. Used only where the value is published by a task the test
    /// cannot await directly.
    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting until \(description)", file: file, line: line)
    }
}

/// Movable clock for the cooldown countdown.
///
/// `@unchecked Sendable`: it is only ever read from the ViewModel's main actor
/// and advanced from the test body, which runs there too.
private final class TestClock: @unchecked Sendable {
    private(set) var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func advance(by seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }
}

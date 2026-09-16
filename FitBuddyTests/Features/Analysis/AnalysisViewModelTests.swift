import Combine
import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisViewModel` (#31, #117): the state machine, the
/// cancel path, and the result age. No network and no Keychain — the stream
/// comes from `StubAnalysisStreamer`, the history from an in-memory store.
@MainActor
final class AnalysisViewModelTests: XCTestCase {
    /// Fixed reference point, so both analysis windows are deterministic.
    private static let reference = Date(timeIntervalSince1970: 1_788_000_000)

    private var cache: StubWorkoutCache!
    private var streamer: StubAnalysisStreamer!
    private var container: ModelContainer!
    private var results: AnalysisResultStore!

    override func setUp() async throws {
        try await super.setUp()
        cache = StubWorkoutCache()
        cache.summaries = [Self.workout(daysAgo: 2), Self.workout(daysAgo: 5)]
        streamer = StubAnalysisStreamer()
        container = try ModelContainerFactory.makeInMemory()
        results = AnalysisResultStore(modelContainer: container)
    }

    override func tearDown() async throws {
        results = nil
        container = nil
        streamer = nil
        cache = nil
        try await super.tearDown()
    }

    /// The clock is passed in rather than held in a property, so no test has to
    /// force-unwrap it. Tests that move time keep their own reference.
    private func makeSUT(
        clock: TestClock = TestClock(AnalysisViewModelTests.reference),
        slowThreshold: TimeInterval = 30,
        tickInterval: TimeInterval = 60,
        resultStore: (any AnalysisResultStoring)? = nil,
        exerciseCache: StubAnalysisExerciseCache? = nil,
        detailCache: StubWorkoutDetailCache? = nil
    ) -> AnalysisViewModel {
        AnalysisViewModel(
            cache: cache,
            exerciseCache: exerciseCache,
            detailCache: detailCache,
            inference: streamer,
            resultStore: resultStore ?? results,
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

    private static func workout(
        daysAgo: Int,
        title: String = "Push Day",
        source: ConnectorSource = .hevy
    ) -> WorkoutSummary {
        WorkoutSummary(
            id: "w-\(daysAgo)",
            title: title,
            startTime: reference.addingTimeInterval(-Double(daysAgo) * 86_400),
            source: source,
            volumeKg: source == .strava ? 0 : 4_200,
            exerciseCount: 5,
            countedSetCount: 18
        )
    }

    // MARK: - Happy path

    func testSuccessfulRunEndsInResult() async {
        await streamer.setText("Your bench volume is rising.")
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose("Your bench volume is rising.")))
        XCTAssertFalse(sut.isTakingLong)
        XCTAssertTrue(sut.canStartAnalysis)
    }

    func testOnlyTheResultCarriesAnOutcome() {
        let report = ValidatedAnalysisReportFixtures.everyCard
        XCTAssertEqual(AnalysisState.result(.prose("whole")).outcome, .prose("whole"))
        XCTAssertEqual(AnalysisState.result(.report(report)).outcome, .report(report))
        XCTAssertNil(AnalysisState.running.outcome)
        XCTAssertNil(AnalysisState.idle.outcome)
        XCTAssertNil(AnalysisState.error(.offline(.claude)).outcome)
        XCTAssertTrue(AnalysisState.running.isRunning)
        XCTAssertFalse(AnalysisState.result(.prose("whole")).isRunning)
        XCTAssertFalse(AnalysisState.idle.isRunning)
        XCTAssertFalse(AnalysisState.error(.offline(.claude)).isRunning)
    }

    func testTheOutcomeReadsAsProse() {
        let report = ValidatedAnalysisReportFixtures.everyCard
        XCTAssertEqual(AnalysisOutcome.report(report).text, report.summary)
        XCTAssertEqual(AnalysisOutcome.report(report).report, report)
        XCTAssertEqual(AnalysisOutcome.prose("whole").text, "whole")
        XCTAssertNil(AnalysisOutcome.prose("whole").report)
    }

    // MARK: - Report in one step (#178)

    /// US-14 #178 AC1/AC3: the screen goes straight from the spinner to the
    /// complete answer. Every state the run publishes is recorded, so no
    /// intermediate state carrying part of the answer can slip through.
    func testNoPartialAnswerIsPublishedBetweenTheSpinnerAndTheResult() async {
        await streamer.setEvents([
            .attempting(.claude),
            .text("An answer from a provider that then fails"),
            .attempting(.gemini),
            .report(AnalysisReportFixtures.progress),
        ])
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache())
        var published: [AnalysisState] = []
        // Combine in a test only: the `@Published` publisher is the one place
        // that sees every state the run publishes, including the ones it
        // passes straight through. CLAUDE.md's "async/await, not Combine"
        // governs the app code.
        let subscription = sut.$state.sink { published.append($0) }

        await sut.start()
        subscription.cancel()

        XCTAssertEqual(published.count, 3, "published \(published)")
        XCTAssertEqual(published.first, .idle)
        XCTAssertEqual(published.dropFirst().first, .running)
        guard case .report(let report)? = published.last?.outcome else {
            return XCTFail("expected a report outcome, got \(String(describing: published.last))")
        }
        XCTAssertEqual(report.summary, AnalysisReportFixtures.progress.summary)
    }

    /// Previews have no exercise cache: the prompt carried no exercise data,
    /// so the cards cannot be checked and the summary is shown instead.
    func testAReportWithoutAnExerciseCacheIsShownAndStoredAsItsSummary() async throws {
        await streamer.setReport(AnalysisReportFixtures.progress)
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose(AnalysisReportFixtures.progress.summary)))
        XCTAssertFalse(sut.isTakingLong)
        let latest = try await results.latest()
        XCTAssertEqual(latest?.text, AnalysisReportFixtures.progress.summary)
        XCTAssertNil(latest?.report)
        XCTAssertEqual(latest?.provider, .claude)
    }

    /// Thin data: a report without cards is still a report — shown and
    /// stored with its lead and summary, not downgraded to prose (#170). A
    /// progress verdict without a progression card holds (#177).
    func testAReportWithoutCardsIsShownAndStoredAsAReport() async throws {
        await streamer.setReport(AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "Too little data for a change yet.",
            cards: [],
            summary: "Keep training as you do."
        ))
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache())

        await sut.start()

        let expected = ValidatedAnalysisReport(
            headline: AnalysisReportValidator.holdHeadline,
            verdict: .hold,
            lead: "Too little data for a change yet.",
            cards: [],
            summary: "Keep training as you do."
        )
        XCTAssertEqual(sut.state, .result(.report(expected)))
        let latest = try await results.latest()
        XCTAssertEqual(latest?.text, "Keep training as you do.")
        XCTAssertEqual(latest?.report, expected)
    }

    /// US-14 AC3: a progression on an exercise the prompt did not list is a
    /// note, one on a listed exercise with the cached working weight stays.
    func testAReportIsValidatedAgainstTheReadsOfTheRun() async throws {
        let bench = Self.exercise("Bench Press", volume: 1_000)
        let exercises = StubAnalysisExerciseCache()
        exercises.exercises = [bench]
        exercises.progressions = [bench.id: Self.progression(bench, weightKg: 60, reps: 5, daysAgo: 2)]
        let reasoning = "Five sessions at 60 kg with the reps held."
        await streamer.setReport(AnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: "Bench press can go up.",
            cards: [
                .progression(exercise: "Bench Press", muscleGroup: "Chest", fromKg: 60, toKg: 62.5, reasoning: reasoning),
                .progression(exercise: "Squat", muscleGroup: "Legs", fromKg: 100, toKg: 102.5, reasoning: "Squat is ready."),
            ],
            summary: "Add 2.5 kg on bench."
        ))
        let sut = makeSUT(exerciseCache: exercises)

        await sut.start()

        let report = try XCTUnwrap(sut.state.outcome?.report)
        XCTAssertEqual(report.cards, [
            .progression(
                exercise: "Bench Press",
                muscleGroup: MuscleGroup.from(exerciseTitle: "Bench Press"),
                fromKg: 60,
                toKg: 62.5,
                reasoning: reasoning
            ),
            .note(title: "Squat", text: "Squat is ready."),
        ])
        XCTAssertEqual(report.verdict, .progress)
        XCTAssertEqual(report.lead, "Bench press can go up.")
    }

    /// US-14 AC4: at six training days of the last seven the app inserts the
    /// recovery card the model left out, with the RPE read from the details.
    func testSixOfSevenTrainingDaysInsertTheRecoveryCardWithTheRPE() async throws {
        cache.summaries = (0...5).map { Self.workout(daysAgo: $0) }
        let details = StubWorkoutDetailCache()
        details.details = (0...5).map { Self.detail(daysAgo: $0, rpe: 8) }
        await streamer.setReport(Self.noteOnlyReport)
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache(), detailCache: details)

        await sut.start()

        let report = try XCTUnwrap(sut.state.outcome?.report)
        XCTAssertEqual(report.verdict, .recover)
        XCTAssertEqual(report.cards.first, .recovery(
            reasoning: AnalysisReportValidator.insertedRecoveryReasoning,
            metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8)
        ))
        XCTAssertEqual(details.callCount, 6)
    }

    /// A failing detail read costs the RPE, not the paid-for answer.
    func testADetailReadFailureValidatesWithoutRPE() async throws {
        cache.summaries = (0...5).map { Self.workout(daysAgo: $0) }
        let details = StubWorkoutDetailCache()
        details.details = (0...5).map { Self.detail(daysAgo: $0, rpe: 8) }
        details.error = StubWorkoutDetailCache.Failure()
        await streamer.setReport(Self.noteOnlyReport)
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache(), detailCache: details)

        await sut.start()

        let report = try XCTUnwrap(sut.state.outcome?.report)
        XCTAssertEqual(report.cards.first, .recovery(
            reasoning: AnalysisReportValidator.insertedRecoveryReasoning,
            metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        ))
        let latest = try await results.latest()
        XCTAssertEqual(latest?.report, report)
    }

    /// A session removed by a sync since the summaries were read makes the
    /// details unavailable as a whole — no mean over part of the week.
    func testAMissingDetailValidatesWithoutRPE() async throws {
        cache.summaries = (0...5).map { Self.workout(daysAgo: $0) }
        let details = StubWorkoutDetailCache()
        details.details = (1...5).map { Self.detail(daysAgo: $0, rpe: 8) }
        await streamer.setReport(Self.noteOnlyReport)
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache(), detailCache: details)

        await sut.start()

        let report = try XCTUnwrap(sut.state.outcome?.report)
        XCTAssertEqual(report.cards.first, .recovery(
            reasoning: AnalysisReportValidator.insertedRecoveryReasoning,
            metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil)
        ))
    }

    /// #178: the details are read with the prompt, before the provider is
    /// called — so the report is validated against one snapshot, and the
    /// answer's own validation reads nothing.
    func testTheDetailsAreReadBeforeTheProviderIsCalled() async {
        cache.summaries = (0...5).map { Self.workout(daysAgo: $0) }
        let details = StubWorkoutDetailCache()
        details.details = (0...5).map { Self.detail(daysAgo: $0, rpe: 8) }
        details.gatesCalls = true
        await streamer.setReport(Self.noteOnlyReport)
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache(), detailCache: details)

        let run = Task { await sut.start() }
        await details.waitForCall()
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)

        details.gatesCalls = false
        details.release()
        await run.value
        XCTAssertEqual(details.callCount, 6)
        XCTAssertNotNil(sut.state.outcome?.report)
    }

    /// A cancel while the details are read ends the run there: nothing is
    /// shown, nothing is stored, and no provider is paid.
    func testCancelDuringTheDetailReadShowsAndStoresNothing() async throws {
        cache.summaries = (0...5).map { Self.workout(daysAgo: $0) }
        let details = StubWorkoutDetailCache()
        details.details = (0...5).map { Self.detail(daysAgo: $0, rpe: 8) }
        details.gatesCalls = true
        await streamer.setReport(Self.noteOnlyReport)
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache(), detailCache: details)

        let run = Task { await sut.start() }
        await details.waitForCall()
        sut.cancel()
        details.release()
        await run.value

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.generatedAt)
        let latest = try await results.latest()
        XCTAssertNil(latest)
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(details.callCount, 1)
    }

    /// US-14 AC5: prose stays prose, even where a report would be validated.
    func testAProseAnswerEndsInTheProseOutcome() async throws {
        await streamer.setText("Give legs a second slot.", from: .mistral)
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache())

        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose("Give legs a second slot.")))
        let latest = try await results.latest()
        XCTAssertEqual(latest?.text, "Give legs a second slot.")
        XCTAssertNil(latest?.report)
        XCTAssertEqual(latest?.provider, .mistral)
    }

    /// US-14 AC6 (#176): the validated report is stored as shown, with its
    /// summary as the prose fallback and the provider, and a restart brings
    /// back the same cards.
    func testTheValidatedReportIsStoredAndRestored() async throws {
        await streamer.setReport(AnalysisReportFixtures.progress, from: .gemini)
        let sut = makeSUT(exerciseCache: StubAnalysisExerciseCache())
        await sut.start()
        let shown = try XCTUnwrap(sut.state.outcome?.report)

        let latest = try await results.latest()
        XCTAssertEqual(latest?.report, shown)
        XCTAssertEqual(latest?.text, shown.summary)
        XCTAssertEqual(latest?.provider, .gemini)

        let restarted = makeSUT()
        await restarted.restore()

        XCTAssertEqual(restarted.state, .result(.report(shown)))
        XCTAssertEqual(restarted.attribution, AnalysisAttribution(first: .gemini))
    }

    /// A report with a single note, so the recovery card in the result can
    /// only have come from the app.
    private static let noteOnlyReport = AnalysisReport(
        headline: "Keep going.",
        verdict: .progress,
        lead: "Add reps before weight.",
        cards: [.note(title: "Reps first", text: "Add a rep on rows before adding weight.")],
        summary: "Add a rep on rows before adding weight."
    )

    /// A session matching `workout(daysAgo:)`, with one counted set per
    /// exercise at `rpe`.
    private static func detail(daysAgo: Int, rpe: Double?) -> WorkoutDetail {
        WorkoutDetail(
            id: "w-\(daysAgo)",
            title: "Push Day",
            workoutDescription: nil,
            startTime: reference.addingTimeInterval(-Double(daysAgo) * 86_400),
            endTime: nil,
            volumeKg: 600,
            countedSetCount: 1,
            exercises: [
                ExerciseDetail(
                    index: 0,
                    title: "Bench Press",
                    sets: [
                        SetDetail(index: 0, type: .normal, weightKg: 60, reps: 10,
                                  distanceMeters: nil, durationSeconds: nil, rpe: rpe),
                    ]
                ),
            ]
        )
    }

    func testRunSendsThePromptBuiltFromTheCachedWindow() async {
        await streamer.setText("ok")
        let sut = makeSUT()

        await sut.start()

        let system = await streamer.systemPrompt
        let user = await streamer.userPrompt
        XCTAssertEqual(system, AnalysisPromptBuilder.systemPrompt)
        XCTAssertEqual(user?.contains("Push Day"), true)
        // Read wide enough for the widest rung of the ladder and its
        // comparison window, so one read serves every fallback step (#87).
        XCTAssertEqual(
            cache.requestedSince,
            AnalysisWindow.widest.previousStart(endingAt: Self.reference, calendar: Self.calendar)
        )
        XCTAssertEqual(sut.context?.window, .default)
    }

    // MARK: - Exercise data (#173)

    /// The run hands the exercise reads to the prompt: the working weight of
    /// the cached session reaches the model.
    func testRunSendsTheExerciseDataToThePrompt() async {
        await streamer.setText("ok")
        let exercises = StubAnalysisExerciseCache()
        let bench = Self.exercise("Bench Press", volume: 4_500)
        exercises.exercises = [bench]
        exercises.progressions = [bench.id: Self.progression(bench, weightKg: 60, reps: 5, daysAgo: 2)]
        let sut = makeSUT(exerciseCache: exercises)

        await sut.start()

        let user = await streamer.userPrompt
        XCTAssertEqual(user?.contains("## Exercises (last 4 weeks)"), true)
        XCTAssertEqual(user?.contains("- Bench Press: 60 kg × 5"), true)
    }

    /// Both reads cover the resolved window — not the 26 weeks the session
    /// read reaches back — so the ranking is by volume in the analysed window.
    func testExerciseReadsCoverTheResolvedWindow() async {
        await streamer.setText("ok")
        let exercises = StubAnalysisExerciseCache()
        let bench = Self.exercise("Bench Press", volume: 4_500)
        exercises.exercises = [bench]
        let sut = makeSUT(exerciseCache: exercises)

        await sut.start()

        let start = AnalysisWindow.default.start(endingAt: Self.reference, calendar: Self.calendar)
        XCTAssertEqual(exercises.requestedSummariesSince, start)
        XCTAssertEqual(exercises.requestedProgressionSince, start)
    }

    /// Progressions are read for the listed movements only.
    func testProgressionsAreReadOnlyForTheListedExercises() async {
        await streamer.setText("ok")
        let exercises = StubAnalysisExerciseCache()
        exercises.exercises = (1...14).map { Self.exercise("Lift \($0)", volume: Double($0) * 100) }
        let sut = makeSUT(exerciseCache: exercises)

        await sut.start()

        let expected = AnalysisPromptBuilder.promptedExercises(from: exercises.exercises).map(\.id)
        XCTAssertEqual(exercises.requestedProgressionIDs, expected)
        XCTAssertEqual(exercises.requestedProgressionIDs.count, AnalysisPromptBuilder.maxListedExercises)
    }

    /// A failing exercise read fails the run like a failing session read —
    /// no provider is paid for a prompt missing the data rule 6 relies on,
    /// and no data basis is left on screen.
    func testExerciseReadFailureIsReportedAsCacheUnavailable() async {
        let exercises = StubAnalysisExerciseCache()
        exercises.error = StubAnalysisExerciseCache.Failure()
        let sut = makeSUT(exerciseCache: exercises)

        await sut.start()

        XCTAssertEqual(sut.state, .error(.cacheUnavailable))
        XCTAssertNil(sut.context)
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    /// Without an exercise cache — the previews' case — the prompt says there
    /// is no exercise data instead of leaving the model to invent weights.
    func testRunWithoutAnExerciseCacheStatesThatThereIsNoExerciseData() async {
        await streamer.setText("ok")
        let sut = makeSUT()

        await sut.start()

        let user = await streamer.userPrompt
        XCTAssertEqual(user?.contains("No exercise-level data is available"), true)
    }

    private static func exercise(_ title: String, volume: Double) -> ExerciseSummary {
        ExerciseSummary(
            id: ExerciseSummary.key(templateID: nil, title: title),
            title: title,
            muscleGroup: MuscleGroup.from(exerciseTitle: title),
            sessionCount: 1,
            countedSetCount: 3,
            volumeKg: volume,
            lastPerformed: reference
        )
    }

    private static func progression(
        _ summary: ExerciseSummary,
        weightKg: Double,
        reps: Int,
        daysAgo: Int
    ) -> ExerciseProgression {
        let sets = (0..<3).map { index in
            SetDetail(
                index: index,
                type: .normal,
                weightKg: weightKg,
                reps: reps,
                distanceMeters: nil,
                durationSeconds: nil,
                rpe: nil
            )
        }
        return ExerciseProgression(
            id: summary.id,
            title: summary.title,
            sessions: [
                ExerciseHistoryEntry(
                    workoutID: "w-\(daysAgo)",
                    sessionStart: reference.addingTimeInterval(-Double(daysAgo) * 86_400),
                    sets: sets
                ),
            ]
        )
    }

    // MARK: - Context (US-6, #36)

    /// The context line counts the sessions of the *analysed* window, not
    /// everything the cache read returned — the read reaches back 26 weeks so
    /// one read serves every rung of the ladder (#87).
    func testContextCountsOnlyTheSessionsInsideTheResolvedWindow() async {
        cache.summaries = [
            Self.workout(daysAgo: 2),
            Self.workout(daysAgo: 20),
            // Outside the 4-week window, inside the read.
            Self.workout(daysAgo: 40),
            Self.workout(daysAgo: 80)
        ]
        await streamer.setText("ok")
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.context?.window, .default)
        XCTAssertEqual(sut.context?.sessionCount, 2)
    }

    /// The context line describes the strength history the prompt was built
    /// from (US-6 AC1): Strava sessions count neither here nor in the prompt.
    func testContextDoesNotCountStravaSessions() async {
        cache.summaries = [
            Self.workout(daysAgo: 2),
            Self.workout(daysAgo: 3, title: "Morning Run", source: .strava),
            Self.workout(daysAgo: 5),
        ]
        await streamer.setText("ok")
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.context?.sessionCount, 2)
    }

    /// A cache holding nothing but runs has no strength history to analyse —
    /// not a window to widen, and not a provider call worth paying for.
    func testACacheOfOnlyStravaSessionsIsNoTrainingData() async {
        cache.summaries = [Self.workout(daysAgo: 2, title: "Morning Run", source: .strava)]
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.noTrainingData))
        XCTAssertNil(sut.context)
    }

    /// After a widened window the count has to follow it: the sessions the
    /// analysis found are exactly the ones the wider rung holds.
    func testContextCountsTheWidenedWindowWhenTheLadderMoves() async {
        cache.summaries = [Self.workout(daysAgo: 40), Self.workout(daysAgo: 50), Self.workout(daysAgo: 80)]
        await streamer.setText("ok")
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.context?.window.weeks, 8)
        XCTAssertEqual(sut.context?.sessionCount, 2)
    }

    /// A run that never resolves a window must not leave the previous run's
    /// basis on screen.
    func testContextIsClearedWhenARunFails() async {
        await streamer.setText("first")
        let clock = TestClock(Self.reference)
        let sut = makeSUT(clock: clock)
        XCTAssertNil(sut.context)

        await sut.start()
        XCTAssertNotNil(sut.context)

        // Later, on a cache that no rung can serve.
        clock.advance(by: 7 * 3_600)
        cache.summaries = []
        await sut.start()

        XCTAssertEqual(sut.state, .error(.noTrainingData))
        XCTAssertNil(sut.context)
    }

    /// The clearing has to happen at the *start* of a run, not only on its
    /// failure path: while the second run is still loading, the first run's
    /// basis would otherwise sit above a recommendation it does not describe.
    func testContextIsClearedWhileANewRunIsStillLoading() async {
        await streamer.setText("first")
        let clock = TestClock(Self.reference)
        let sut = makeSUT(clock: clock)

        await sut.start()
        XCTAssertNotNil(sut.context)

        // Later, second run held inside the cache read — after
        // the clearing, before the window is resolved.
        clock.advance(by: 7 * 3_600)
        await streamer.setText("second")
        cache.gatesFirstCall = true
        cache.gatedCall = 2
        let run = Task { await sut.start() }
        await cache.waitForFirstCall()

        XCTAssertEqual(sut.state, .running)
        XCTAssertNil(sut.context)

        cache.releaseFirstCall()
        await run.value
        XCTAssertNotNil(sut.context)
    }

    /// The state has to pass through `.running` before the answer arrives —
    /// that is the spinner phase of US-3 AC1.
    func testStateIsRunningBeforeTheAnswer() async {
        await streamer.gateCall()
        await streamer.setText("done")
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        XCTAssertEqual(sut.state, .running)

        await streamer.release()
        await run.value
        XCTAssertEqual(sut.state, .result(.prose("done")))
    }

    // MARK: - Guards

    /// #87: an empty 4-week window is "no *recent* data", not "no data" — the
    /// window widens and the run goes through.
    func testEmptyFourWeekWindowRunsOverTheWidenedWindow() async {
        cache.summaries = [Self.workout(daysAgo: 40)]
        await streamer.setText("Back after a break.")
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose("Back after a break.")))
        XCTAssertEqual(sut.context?.window.weeks, 8)
        let user = await streamer.userPrompt
        XCTAssertEqual(user?.contains("## Last 8 weeks ("), true)
    }

    func testEmptyEightWeekWindowWidensTo13Weeks() async {
        cache.summaries = [Self.workout(daysAgo: 80)]
        await streamer.setText("ok")
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose("ok")))
        XCTAssertEqual(sut.context?.window.weeks, 13)
    }

    /// Only a cache with nothing in the widest window is genuinely empty —
    /// and that one still costs no Claude call.
    func testFullyEmptyCacheFailsWithoutCallingClaude() async {
        cache.summaries = []
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.noTrainingData))
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    /// Everything older than the cache window is out of reach of every rung,
    /// so it is `.noTrainingData` too — the dashboard would not have offered
    /// the button for it either.
    func testWorkoutsOlderThanTheWidestWindowStillFail() async {
        cache.summaries = [Self.workout(daysAgo: 120)]
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.noTrainingData))
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    /// The window belongs to the run on screen: a second run over recent data
    /// must not keep the previous run's widened label.
    func testWindowResetsToTheDefaultOnANewRun() async {
        cache.summaries = [Self.workout(daysAgo: 40)]
        await streamer.setText("first")
        let clock = TestClock(Self.reference)
        let sut = makeSUT(clock: clock)

        await sut.start()
        XCTAssertEqual(sut.context?.window.weeks, 8)

        // Later, with recent training in the cache this time.
        clock.advance(by: 7 * 3_600)
        cache.summaries = [Self.workout(daysAgo: 2)]
        await streamer.setText("second")
        await sut.start()

        XCTAssertEqual(sut.context?.window, .default)
    }

    func testCacheFailureIsReportedAsCacheUnavailable() async {
        cache.error = StubWorkoutCache.Failure()
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.cacheUnavailable))
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    /// No cooldown: the moment a run has ended, the next one starts and
    /// reaches the provider — at the same instant on the clock.
    func testANewRunStartsRightAfterAFinishedOne() async {
        await streamer.setText("first")
        let sut = makeSUT()
        await sut.start()
        XCTAssertEqual(sut.state, .result(.prose("first")))
        XCTAssertTrue(sut.canStartAnalysis)

        await streamer.setText("second")
        sut.reset()
        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose("second")))
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 2)
    }

    /// No cooldown after a failure either: "Try again" reaches the provider.
    func testARetryAfterAFailureReachesTheProvider() async {
        await streamer.setStartError(InferenceServiceError.networkUnavailable)
        let sut = makeSUT()
        await sut.start()
        XCTAssertEqual(sut.state, .error(.offline(nil)))

        await streamer.setStartError(nil)
        await streamer.setText("done")
        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose("done")))
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 2)
    }

    /// A double tap must not buy two analyses.
    func testSecondStartWhileRunningIsIgnored() async {
        await streamer.gateCall()
        await streamer.setText("done")
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        XCTAssertFalse(sut.canStartAnalysis)
        await sut.start()

        await streamer.release()
        await run.value
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 1)
    }

    /// Both taps land before the first run has passed its first await, where
    /// the state is still `.idle` unless the slot is claimed synchronously.
    func testTwoTapsInTheSameRunLoopStartOnlyOneRun() async {
        await streamer.setText("done")
        let sut = makeSUT()

        async let first: Void = sut.start()
        async let second: Void = sut.start()
        _ = await (first, second)

        let calls = await streamer.callCount
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(sut.state, .result(.prose("done")))
    }

    /// A cancel while the prompt is still being built must not be overrun by
    /// the run it stopped before it reached the service.
    func testCancelBeforeTheCallReachesTheServiceStopsTheRun() async {
        await streamer.setText("never rendered")
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await Task.yield()
        sut.cancel()
        await run.value

        XCTAssertEqual(sut.state, .idle)
        let calls = await streamer.callCount
        XCTAssertEqual(calls, 0)
    }

    // MARK: - Failures

    func testStartFailureIsMappedOntoTheScreen() async {
        await streamer.setStartError(InferenceServiceError.missingAPIKey)
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.missingAPIKey))
    }

    // MARK: - Provider attribution (#79)

    func testPublishesTheAnsweringProvider() async {
        await streamer.setText("Recommendation", from: .gemini)
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.attribution?.provider, .gemini)
        XCTAssertEqual(sut.attribution?.attempted, [.gemini])
        XCTAssertEqual(sut.attribution?.didFallBack, false)
    }

    func testAFallbackRecordsBothProvidersInOrder() async {
        await streamer.setEvents([
            .attempting(.claude),
            .attempting(.gemini),
            .text("Recommendation"),
        ])
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.attribution?.attempted, [.claude, .gemini])
        XCTAssertEqual(sut.attribution?.didFallBack, true)
        XCTAssertEqual(sut.attribution?.fallbackNotice, "Claude unavailable — answered by Gemini")
    }

    /// #176: the history badge names the provider that wrote the answer, not
    /// the one the user ranked first.
    func testAFallbackPersistsTheProviderThatAnswered() async throws {
        await streamer.setEvents([
            .attempting(.claude),
            .attempting(.gemini),
            .text("Recommendation"),
        ])
        let sut = makeSUT()

        await sut.start()

        let latest = try await results.latest()
        XCTAssertEqual(latest?.text, "Recommendation")
        XCTAssertEqual(latest?.provider, .gemini)
    }

    /// DoD: the user never sees two answers merged. Whatever the failed
    /// provider already streamed is dropped when the next one takes over.
    func testDiscardsTheAnswerOfAProviderThatGaveWay() async {
        await streamer.setEvents([
            .attempting(.claude),
            .text("A Claude answer that is then discarded"),
            .attempting(.gemini),
            .text("A complete Gemini answer."),
        ])
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .result(.prose("A complete Gemini answer.")))
    }

    /// A run that failed with nothing on screen still has to say who was tried,
    /// or the error view cannot tell a one-provider failure from a chain that
    /// fell all the way through.
    func testKeepsTheAttributionOnAFailedRun() async {
        await streamer.setEvents([.attempting(.claude), .attempting(.mistral)])
        await streamer.setStreamError(InferenceServiceError.serviceUnavailable)
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.serviceUnavailable(.mistral)))
        XCTAssertEqual(sut.attribution?.attempted, [.claude, .mistral])
    }

    /// The error names the provider that actually failed last, not the one the
    /// user ranked first.
    func testTheErrorNamesTheLastProviderTried() async {
        await streamer.setEvents([.attempting(.claude), .attempting(.gemini)])
        await streamer.setStreamError(InferenceServiceError.unauthorized)
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.unauthorized(.gemini)))
    }

    /// No provider was ever announced (no key, cache failure), so
    /// there is nothing to attribute.
    func testLeavesTheAttributionEmptyWhenNoProviderWasTried() async {
        await streamer.setStartError(InferenceServiceError.missingAPIKey)
        let sut = makeSUT()

        await sut.start()

        XCTAssertNil(sut.attribution)
        XCTAssertEqual(sut.state, .error(.missingAPIKey))
    }

    /// A new run starts without the previous run's providers: they have
    /// nothing to do with who answers this one.
    func testANewRunDoesNotInheritThePreviousRunsAttribution() async {
        await streamer.setEvents([.attempting(.claude), .attempting(.gemini), .text("Recommendation")])
        let sut = makeSUT()
        await sut.start()
        XCTAssertEqual(sut.attribution?.attempted, [.claude, .gemini])

        await streamer.setEvents([.attempting(.mistral), .text("Another")])
        await sut.start()

        XCTAssertEqual(sut.attribution?.attempted, [.mistral])
    }

    func testResetClearsTheAttribution() async {
        await streamer.setText("Recommendation")
        let sut = makeSUT()
        await sut.start()
        XCTAssertNotNil(sut.attribution)

        sut.reset()

        XCTAssertNil(sut.attribution)
    }

    /// A stream that dies half-way is a failure, not a short recommendation.
    func testMidStreamFailureDiscardsTheCollectedAnswer() async {
        await streamer.setText("Your training ")
        await streamer.setStreamError(InferenceServiceError.streamInterrupted(message: "overloaded"))
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.serviceUnavailable(.claude)))
    }

    func testStreamWithoutAnyTokenIsAnUnreadableResponse() async {
        await streamer.setEvents([.attempting(.claude)])
        let sut = makeSUT()

        await sut.start()

        XCTAssertEqual(sut.state, .error(.unreadableResponse(.claude)))
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
        await streamer.setText("never rendered")
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
        await streamer.setText("done")
        let sut = makeSUT()
        await sut.start()

        sut.cancel()

        XCTAssertEqual(sut.state, .result(.prose("done")))
    }

    func testResetClearsAFinishedRun() async {
        await streamer.setText("done")
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

    /// An answer from a provider that later gave way stops the timer. If the
    /// handover does not restart it, a second provider that hangs shows a
    /// bare spinner with no way to cancel it — the affordance US-3 AC1 exists
    /// for.
    func testTheSlowHintComesBackWhenAnotherProviderTakesOver() async {
        await streamer.setEvents([
            .attempting(.claude),
            .text("A Claude answer that is then discarded"),
            .attempting(.gemini),
        ])
        await streamer.holdOpenAfterEvents()
        let sut = makeSUT(slowThreshold: 0.05)

        let run = Task { await sut.start() }
        await waitUntil("the slow hint returns for the provider that took over") { sut.isTakingLong }

        XCTAssertEqual(sut.state, .running)
        sut.cancel()
        await run.value
    }

    /// The production handover: the provider that gave way sent no answer, so
    /// the hint has been counting since the tap and must stay up — the cancel
    /// button the user may be reaching for does not disappear (US-3 AC1).
    func testAHandoverKeepsTheSlowHintThatIsAlreadyShowing() async {
        await streamer.setEvents([.attempting(.claude), .attempting(.gemini)])
        await streamer.pauseAfterEvents(1)
        await streamer.holdOpenAfterEvents()
        let sut = makeSUT(slowThreshold: 0.05)

        let run = Task { await sut.start() }
        await waitUntil("the slow hint appears for the first provider") { sut.isTakingLong }

        await streamer.resumeEvents()
        await waitUntil("the handover reaches the screen") { sut.attribution?.attempted == [.claude, .gemini] }

        XCTAssertTrue(sut.isTakingLong)
        XCTAssertEqual(sut.state, .running)
        sut.cancel()
        await run.value
    }

    func testFastRunNeverAnnouncesItselfAsSlow() async {
        await streamer.setText("done")
        let sut = makeSUT(slowThreshold: 60)

        await sut.start()

        XCTAssertFalse(sut.isTakingLong)
    }

    // MARK: - Result age ticker

    /// The ticker keeps the age of the recommendation on screen current, so a
    /// screen left open does not keep claiming "just now".
    func testTheTickerRefreshesTheResultAge() async throws {
        let clock = TestClock(Self.reference)
        try await storeRecommendation(at: Self.reference)
        let sut = makeSUT(clock: clock, tickInterval: 0.01)
        await sut.restore()
        XCTAssertEqual(sut.resultAge, "just now")

        let ticker = Task { await sut.trackResultAge() }
        clock.advance(by: 2 * 3_600)
        await waitUntil("the age follows the clock") {
            sut.resultAge == "2 h ago"
        }

        ticker.cancel()
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

/// Movable clock for windows and the result age.
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

// MARK: - Persistence & restore (#97)

extension AnalysisViewModelTests {
    /// Storing a recommendation as if a previous session had produced it.
    @discardableResult
    private func storeRecommendation(
        _ text: String = "Add 2.5 kg on bench next session.",
        at date: Date,
        sessions: Int = 12,
        window: AnalysisWindow = .default
    ) async throws -> UUID {
        try await results.save(
            text: text,
            generatedAt: date,
            context: AnalysisContext(sessionCount: sessions, window: window)
        )
    }

    func testFinishedRunPersistsTheRecommendation() async throws {
        await streamer.setText("Your bench volume is rising.")
        let sut = makeSUT()

        await sut.start()

        let latest = try await results.latest()
        let stored = try XCTUnwrap(latest)
        XCTAssertEqual(stored.text, "Your bench volume is rising.")
        XCTAssertEqual(stored.generatedAt, Self.reference)
        // Two sessions in the default window, from the `setUp` cache.
        XCTAssertEqual(stored.context, AnalysisContext(sessionCount: 2, window: .default))
        XCTAssertEqual(sut.generatedAt, Self.reference)
        XCTAssertEqual(sut.resultAge, "just now")
    }

    /// #87/#36: the widened window and its count are what the advice actually
    /// rests on, so they are what gets stored.
    func testPersistedContextIsTheOneTheRunResolved() async throws {
        cache.summaries = [Self.workout(daysAgo: 40)]
        await streamer.setText("Back after a break.")
        let sut = makeSUT()

        await sut.start()

        let stored = try await results.latest()
        XCTAssertEqual(stored?.context.window.weeks, 8)
        XCTAssertEqual(stored?.context.sessionCount, 1)
    }

    /// A cancelled run produces no recommendation, and must not cost the user
    /// the one they already have.
    func testCancelledRunKeepsThePreviousStoredRecommendation() async throws {
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-7 * 3_600))
        await streamer.gateCall()
        await streamer.setText("never rendered")
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        sut.cancel()
        await streamer.release()
        await run.value

        let stored = try await results.latest()
        XCTAssertEqual(stored?.text, "Add 2.5 kg on bench next session.")
    }

    func testFailedRunKeepsThePreviousStoredRecommendation() async throws {
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-7 * 3_600))
        await streamer.setStartError(.networkUnavailable)
        let sut = makeSUT()

        await sut.start()

        let stored = try await results.latest()
        XCTAssertEqual(stored?.text, "Add 2.5 kg on bench next session.")
    }

    /// A stream with no token is a response this build could not read — not an
    /// empty recommendation worth storing.
    func testUnreadableResponseKeepsThePreviousStoredRecommendation() async throws {
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-7 * 3_600))
        await streamer.setEvents([.attempting(.claude)])
        let sut = makeSUT()

        await sut.start()

        let stored = try await results.latest()
        XCTAssertEqual(stored?.text, "Add 2.5 kg on bench next session.")
    }

    /// US-3 AC10: reopening the app shows the last
    /// recommendation instead of the intro screen.
    func testRestoreBringsBackTheStoredRecommendation() async throws {
        try await storeRecommendation(
            "Give legs a second slot.",
            at: Self.reference.addingTimeInterval(-2 * 3_600),
            sessions: 6,
            window: AnalysisWindow(weeks: 8)
        )
        let sut = makeSUT()

        await sut.restore()

        XCTAssertEqual(sut.state, .result(.prose("Give legs a second slot.")))
        // #36: the restored screen names the basis of the run that produced
        // the text, not a basis re-counted from today's cache.
        XCTAssertEqual(sut.context, AnalysisContext(sessionCount: 6, window: AnalysisWindow(weeks: 8)))
        XCTAssertEqual(sut.resultAge, "2 h ago")
        // No provider is stored, so the badge falls back to the bare "AI".
        XCTAssertNil(sut.attribution)
    }

    /// #176: a row that recorded its provider is restored with it, so the
    /// badge reads "AI · Gemini" — and without the fallback notice, since the
    /// chain that led there is not stored.
    func testRestoreBringsBackTheStoredProvider() async throws {
        try await results.save(
            text: "Give legs a second slot.",
            report: nil,
            provider: .gemini,
            generatedAt: Self.reference.addingTimeInterval(-2 * 3_600),
            context: AnalysisContext(sessionCount: 6, window: .default)
        )
        let sut = makeSUT()

        await sut.restore()

        XCTAssertEqual(sut.state, .result(.prose("Give legs a second slot.")))
        XCTAssertEqual(sut.attribution, AnalysisAttribution(first: .gemini))
        XCTAssertEqual(sut.attribution?.provider.displayName, "Gemini")
        XCTAssertEqual(sut.attribution?.didFallBack, false)
        XCTAssertNil(sut.attribution?.fallbackNotice)
    }

    func testRestoreWithoutAStoredRecommendationLeavesTheIntroScreen() async {
        let sut = makeSUT()

        await sut.restore()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.resultAge)
    }

    // MARK: - History entry point (#117)

    func testASingleStoredAnalysisIsNoHistory() async throws {
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        let sut = makeSUT()

        await sut.restore()

        XCTAssertFalse(sut.hasHistory)
    }

    func testASecondStoredAnalysisOpensTheHistory() async throws {
        try await storeRecommendation("Older advice.", at: Self.reference.addingTimeInterval(-9 * 3_600))
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        let sut = makeSUT()

        await sut.restore()

        XCTAssertTrue(sut.hasHistory)
    }

    /// The run that finishes here is the second stored analysis, so the link
    /// has to appear without the screen being reopened.
    func testAFinishedRunOpensTheHistoryOnTheFirstRepeat() async throws {
        try await storeRecommendation("Older advice.", at: Self.reference.addingTimeInterval(-9 * 3_600))
        await streamer.setText("Fresh advice.")
        let sut = makeSUT()

        await sut.start()

        XCTAssertTrue(sut.hasHistory)
    }

    /// Deleting everything but the recommendation on screen closes the link
    /// again — there is nothing behind it any more.
    func testRefreshHistoryClosesTheLinkOnceOnlyOneAnalysisIsLeft() async throws {
        let older = try await storeRecommendation(
            "Older advice.",
            at: Self.reference.addingTimeInterval(-9 * 3_600)
        )
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        let sut = makeSUT()
        await sut.restore()
        XCTAssertTrue(sut.hasHistory)

        try await results.delete(id: older)
        await sut.refreshHistory()

        XCTAssertFalse(sut.hasHistory)
        XCTAssertEqual(sut.state, .result(.prose("Add 2.5 kg on bench next session.")))
    }

    /// Deleting the analysis on screen from the history must take it off the
    /// screen too — it is the one text in the app whose deletion the user can
    /// watch not happening.
    func testDeletingTheShownAnalysisFallsBackToTheOneBehindIt() async throws {
        try await storeRecommendation("Older advice.", at: Self.reference.addingTimeInterval(-9 * 3_600))
        let newest = try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        let sut = makeSUT()
        await sut.restore()
        XCTAssertEqual(sut.state, .result(.prose("Add 2.5 kg on bench next session.")))

        try await results.delete(id: newest)
        await sut.refreshHistory()

        XCTAssertEqual(sut.state, .result(.prose("Older advice.")))
        XCTAssertFalse(sut.hasHistory)
    }

    /// The last one deleted leaves the intro screen, not a recommendation that
    /// is no longer stored.
    func testDeletingTheOnlyAnalysisLeavesTheIntroScreen() async throws {
        let only = try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        let sut = makeSUT()
        await sut.restore()

        try await results.delete(id: only)
        await sut.refreshHistory()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.resultAge)
    }

    /// What is on screen is at least as current as what is on disk.
    func testRestoreDoesNotOverwriteARunInFlight() async throws {
        try await storeRecommendation("Older advice.", at: Self.reference.addingTimeInterval(-7 * 3_600))
        await streamer.gateCall()
        await streamer.setText("Fresh advice.")
        let sut = makeSUT()

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        await sut.restore()
        XCTAssertEqual(sut.state, .running)

        await streamer.release()
        await run.value
        XCTAssertEqual(sut.state, .result(.prose("Fresh advice.")))
    }

    /// "New analysis" must survive a reopened sheet: `AnalysisView.task` runs
    /// again, and a second restore would put the recommendation right back.
    func testRestoreDoesNotUndoADismissedRecommendation() async throws {
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        let sut = makeSUT()
        await sut.restore()

        sut.reset()
        await sut.restore()

        XCTAssertEqual(sut.state, .idle)
    }

    /// The dismissal only holds until the run the user asked for is under way.
    /// A run that then fails leaves the screen empty while the recommendation
    /// is still on disk — the dead end #97 exists to remove.
    func testFailedRunAfterANewAnalysisTapBringsTheStoredRecommendationBack() async throws {
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        await streamer.setStartError(InferenceServiceError.missingAPIKey)
        let sut = makeSUT()
        await sut.restore()
        sut.reset()

        await sut.start()
        XCTAssertEqual(sut.state, .error(.missingAPIKey))
        await sut.dismissFailure()

        XCTAssertEqual(sut.state, .result(.prose("Add 2.5 kg on bench next session.")))
        XCTAssertEqual(sut.resultAge, "2 h ago")
    }

    /// The run stays in flight until its answer is stored: "New analysis"
    /// must not start a second run while the first one is still writing, and
    /// the moment it is done, the next run is allowed.
    func testTheRunStaysInFlightWhileItPersists() async throws {
        let gate = GatedAnalysisResultStore(wrapping: results)
        await streamer.gateCall()
        await streamer.setText("done")
        let sut = makeSUT(resultStore: gate)

        let run = Task { await sut.start() }
        await streamer.waitForCall()
        await streamer.release()

        await gate.waitForSave()
        XCTAssertEqual(sut.state, .running, "The run must still read as in flight while it persists")
        XCTAssertFalse(sut.canStartAnalysis)
        await sut.start()
        let callsDuringSave = await streamer.callCount
        XCTAssertEqual(callsDuringSave, 1, "A tap during the write must not start a second run")

        await gate.releaseSave()
        await run.value
        XCTAssertEqual(sut.state, .result(.prose("done")))
        XCTAssertTrue(sut.canStartAnalysis)
    }

    /// "Back" on the very first run's error screen has nothing to fall back
    /// to, and must leave the intro screen rather than an empty result.
    func testDismissFailureWithoutAStoredRecommendationLeavesTheIntroScreen() async {
        await streamer.setStartError(InferenceServiceError.missingAPIKey)
        let sut = makeSUT()
        await sut.start()

        await sut.dismissFailure()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.generatedAt)
    }

    /// A run started while `restore()` is still reading the store must not be
    /// replaced by the older recommendation the restore comes back with.
    func testRestoreDoesNotOverwriteARunStartedMeanwhile() async throws {
        let generatedAt = Self.reference.addingTimeInterval(-7 * 3_600)
        try await storeRecommendation("Older advice.", at: generatedAt)
        await streamer.setText("Fresh advice.")
        let sut = makeSUT()

        // Both run concurrently, the way a tap on "Analyze" lands while the
        // view's restore task is still in flight.
        async let restored: Void = sut.restore()
        async let run: Void = sut.start()
        _ = await (restored, run)

        XCTAssertEqual(sut.state, .result(.prose("Fresh advice.")))
    }

    /// "New analysis" only clears the screen — the recommendation stays on
    /// disk until a later run replaces it.
    func testResetClearsTheScreenButKeepsTheStoredRecommendation() async throws {
        try await storeRecommendation(at: Self.reference.addingTimeInterval(-2 * 3_600))
        let sut = makeSUT()
        await sut.restore()

        sut.reset()

        XCTAssertEqual(sut.state, .idle)
        XCTAssertNil(sut.generatedAt)
        XCTAssertNil(sut.resultAge)
        XCTAssertNil(sut.context)
        let stored = try await results.latest()
        XCTAssertEqual(stored?.text, "Add 2.5 kg on bench next session.")
    }

    /// The age is re-rendered against the clock, so a screen left open does
    /// not keep claiming "just now".
    func testResultAgeAgesWithTheClock() async throws {
        let clock = TestClock(Self.reference)
        try await storeRecommendation(at: Self.reference)
        let sut = makeSUT(clock: clock)
        await sut.restore()
        XCTAssertEqual(sut.resultAge, "just now")

        clock.advance(by: 2 * 3_600)
        sut.refreshResultAge()

        XCTAssertEqual(sut.resultAge, "2 h ago")
    }
}

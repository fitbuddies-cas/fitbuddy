import SwiftData
import XCTest
@testable import FitBuddy

// The mock profiles are DEBUG-only, like the loader that reads them.
#if DEBUG

/// The two analysis mock profiles run through the real pipeline (#179): the
/// bundled payload is cached through `WorkoutStore`, `AnalysisViewModel` reads
/// it and builds the prompt, a model answer from `AnalysisReportFactory` comes
/// back, and the validator turns it into the cards the screen shows.
///
/// What the unit tests of each step cannot show on their own: that the cache
/// reads, the prompt and the validator agree on the same recorded history —
/// US-14 AC2 for `progression-ready`, AC4 for `overreached`.
@MainActor
final class AnalysisMockProfileTests: XCTestCase {
    /// 10:40 UTC. The loader moves each profile's newest session into the 24
    /// hours before it, so the history is always recent.
    private static let morning = Date(timeIntervalSince1970: 1_788_000_000)
    /// 20:40 UTC the same day: the newest session lands on the reference day
    /// itself rather than the day before.
    private static let evening = morning.addingTimeInterval(10 * 3_600)

    /// Fixed time zone, so day boundaries do not move with the machine.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    private var container: ModelContainer!
    private var store: WorkoutStore!
    private var streamer: StubAnalysisStreamer!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.makeInMemory()
        store = WorkoutStore(modelContainer: container)
        streamer = StubAnalysisStreamer()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        streamer = nil
        store = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - progression-ready (US-14 AC2)

    func testProgressionReadyPromptNamesBenchAtSixtyKilosTimesFiveWithTheRPE() async throws {
        let prompt = try await run(.progressionReady, answer: AnalysisReportFactory.progressionReady).prompt

        let bench = try row(startingWith: "- Bench Press (Barbell): ", in: prompt)
        XCTAssertTrue(
            bench.hasPrefix("- Bench Press (Barbell): 60 kg × 5, mean RPE 7 (most recent session, "),
            bench
        )
        XCTAssertTrue(bench.contains("Chest, "), bench)
        XCTAssertTrue(bench.contains("Plateau: no"), bench)
        XCTAssertTrue(bench.contains("Smallest logged step: 2.5 kg"), bench)
        XCTAssertTrue(prompt.contains("(most recent): 3 sessions"))
    }

    func testProgressionReadyKeepsTheProgressionCard() async throws {
        let outcome = try await run(.progressionReady, answer: AnalysisReportFactory.progressionReady).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report, ValidatedAnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            cards: [
                .progression(
                    exercise: "Bench Press (Barbell)",
                    muscleGroup: .chest,
                    fromKg: 60,
                    toKg: 62.5,
                    reasoning: "3 sessions at 60 kg × 5 with RPE 7 or lower — clean overload signal."
                ),
            ],
            summary: AnalysisReportFactory.progressionReady.summary
        ))
    }

    func testProgressionReadyNeedsNoRecoveryAtAnyTimeOfDay() async throws {
        for now in [Self.morning, Self.evening] {
            let metrics = try await recoveryMetrics(for: .progressionReady, now: now)

            XCTAssertEqual(metrics.trainingDays, 3)
            XCTAssertFalse(metrics.needsRecovery)
        }
    }

    // MARK: - overreached (US-14 AC4)

    func testOverreachedPromptShowsTheSixSessionWeek() async throws {
        let prompt = try await run(.overreached, answer: AnalysisReportFactory.overreached).prompt

        XCTAssertTrue(prompt.contains("(most recent): 6 sessions"))
        let bench = try row(startingWith: "- Bench Press (Barbell): ", in: prompt)
        XCTAssertTrue(
            bench.hasPrefix("- Bench Press (Barbell): 70 kg × 5, mean RPE 8.5 (most recent session, "),
            bench
        )
    }

    /// The recovery figures come from the same cache, over the same seven
    /// days as the prompt's most recent week — whichever day the newest
    /// session lands on.
    func testOverreachedCallsForRecoveryAtAnyTimeOfDay() async throws {
        for now in [Self.morning, Self.evening] {
            let metrics = try await recoveryMetrics(for: .overreached, now: now)

            XCTAssertEqual(metrics, RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.5))
            XCTAssertTrue(metrics.needsRecovery)
            XCTAssertEqual(metrics.suggestedRestHours, 48)
        }
    }

    /// The model missed the week and only proposed a load increase: the app
    /// puts the recovery card first and turns the verdict.
    func testOverreachedInsertsTheRecoveryCardAndTurnsTheVerdict() async throws {
        let outcome = try await run(.overreached, answer: AnalysisReportFactory.overreached).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report.verdict, .recover)
        XCTAssertEqual(report.headline, AnalysisReportValidator.recoveryHeadline)
        XCTAssertEqual(report.cards, [
            .recovery(
                reasoning: AnalysisReportValidator.insertedRecoveryReasoning,
                metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.5)
            ),
            .progression(
                exercise: "Bench Press (Barbell)",
                muscleGroup: .chest,
                fromKg: 70,
                toKg: 72.5,
                reasoning: "Two sessions at 70 kg × 5 this week."
            ),
        ])
    }

    // MARK: - Helpers

    /// Caches `profile` as of `now` and runs one analysis that `answer`
    /// completes.
    private func run(
        _ profile: MockWorkoutProfile,
        answer: AnalysisReport,
        now: Date = AnalysisMockProfileTests.morning
    ) async throws -> (prompt: String, outcome: AnalysisOutcome?) {
        try await seed(profile, now: now)
        await streamer.setReport(answer)
        let sut = AnalysisViewModel(
            cache: store,
            exerciseCache: store,
            detailCache: store,
            inference: streamer,
            rateLimit: AnalysisRateLimitStore(defaults: defaults),
            calendar: Self.calendar,
            now: { now }
        )

        await sut.start()

        let userPrompt = await streamer.userPrompt
        let prompt = try XCTUnwrap(userPrompt, "The analysis never reached the provider")
        return (prompt, sut.state.outcome)
    }

    /// The recovery figures read from the cache the way `AnalysisViewModel`
    /// reads them.
    private func recoveryMetrics(for profile: MockWorkoutProfile, now: Date) async throws -> RecoveryMetrics {
        try await seed(profile, now: now)
        let summaries = try await store.workoutSummaries(since: now.addingTimeInterval(-14 * 86_400))
        var details: [WorkoutDetail] = []
        for session in RecoveryMetrics.lastSevenDaysSessions(in: summaries, now: now, calendar: Self.calendar) {
            let detail = try await store.workoutDetail(id: session.id)
            details.append(try XCTUnwrap(detail))
        }
        return RecoveryMetrics(summaries: summaries, details: details, now: now, calendar: Self.calendar)
    }

    private func seed(_ profile: MockWorkoutProfile, now: Date) async throws {
        let activities = try MockWorkoutLoader(now: { now }).activities(for: profile)
        try await store.replaceCachedWorkouts(from: .hevy, with: activities)
    }

    private func row(startingWith prefix: String, in prompt: String) throws -> String {
        try XCTUnwrap(
            prompt.split(separator: "\n").map(String.init).first { $0.hasPrefix(prefix) },
            "No prompt line starts with \"\(prefix)\""
        )
    }
}

#endif

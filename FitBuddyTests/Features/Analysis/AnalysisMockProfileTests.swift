import SwiftData
import XCTest
@testable import FitBuddy

// The mock profiles are DEBUG-only, like the loader that reads them.
#if DEBUG

/// The analysis mock profiles run through the real pipeline (#179, #188): the
/// bundled payloads are cached through `WorkoutStore`, `AnalysisViewModel`
/// reads them and builds the prompt, a model answer from
/// `AnalysisReportFactory` comes back, and the validator turns it into the
/// cards the screen shows.
///
/// What the unit tests of each step cannot show on their own: that the cache
/// reads, the prompt and the validator agree on the same recorded history —
/// US-14 AC2 for `progression-ready`, AC4 for `overreached`, and US-15 AC1 to
/// AC5 for the three cross-source profiles, whose sessions reach the cache
/// through Strava's and Polar's own DTOs rather than as fixtures.
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
        // Prescribed at 3 × 3 and closed at 60 kg × 5 three times: the 2-for-2
        // rule is met, and the line names the barbell range up to the chest
        // ceiling (ADR-013, #233).
        XCTAssertTrue(bench.hasSuffix("Rep target 3, beaten by 2+ reps in the last 2 sessions. Next: 62.5–65 kg."), bench)
        XCTAssertTrue(prompt.contains("(most recent): 3 sessions"))
    }

    func testProgressionReadyKeepsTheProgressionCard() async throws {
        let outcome = try await run(.progressionReady, answer: AnalysisReportFactory.progressionReady).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report, ValidatedAnalysisReport(
            headline: "You're ready to progress.",
            verdict: .progress,
            lead: AnalysisReportFactory.progressionReady.lead,
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

    // MARK: - plateau (US-17 AC1–AC3, AC7, #235)

    /// The four exercise lines, one per case of ADR-013: the range where the
    /// rule is met and a step exists, reps where it is not met, reps where it
    /// is met but no step is logged, and reps where no target is on file.
    func testPlateauPromptNamesTheRangeAndTheThreeTwoForTwoCases() async throws {
        let prompt = try await run(.plateau, answer: AnalysisReportFactory.plateau).prompt

        let squat = try row(startingWith: "- Squat (Barbell): ", in: prompt)
        XCTAssertTrue(squat.hasPrefix("- Squat (Barbell): 97.5 kg × 5, mean RPE 7.5 (most recent session, "), squat)
        XCTAssertTrue(squat.contains("Plateau: no"), squat)
        // Legs, 10 % of 97.5 is 107.25: three barbell steps, 100 to 105 kg.
        XCTAssertTrue(squat.hasSuffix("Rep target 3, beaten by 2+ reps in the last 2 sessions. Next: 100–105 kg."), squat)

        let bench = try row(startingWith: "- Bench Press (Barbell): ", in: prompt)
        XCTAssertTrue(bench.hasPrefix("- Bench Press (Barbell): 60 kg × 5, mean RPE 8 (most recent session, "), bench)
        XCTAssertTrue(bench.contains("Plateau: yes, no new e1RM best in the last 3 sessions"), bench)
        XCTAssertTrue(bench.hasSuffix("Rep target 5, not yet beaten by 2+ reps in 2 consecutive sessions. Next: progress reps, not weight."), bench)

        let raise = try row(startingWith: "- Lateral Raise (Dumbbell): ", in: prompt)
        XCTAssertTrue(raise.hasSuffix("Rep target 10, beaten by 2+ reps in the last 2 sessions. Next: progress reps, no load step is logged for this exercise."), raise)

        let rows = try row(startingWith: "- Seated Row (Cable): ", in: prompt)
        XCTAssertTrue(rows.hasSuffix("No rep target on file. Next: progress reps, not weight."), rows)
    }

    /// End to end (#235): the squat step within the band survives with the
    /// cache's starting weight, the rep progression survives with the cache's
    /// weight, and the two load increases the rule holds back — not met, not
    /// checkable — become notes. The verdict keeps the model's lead: two
    /// cards still back it.
    func testPlateauKeepsTheCardsTheRuleAllowsAndNotesTheOthers() async throws {
        let outcome = try await run(.plateau, answer: AnalysisReportFactory.plateau).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report.verdict, .progress)
        XCTAssertEqual(report.lead, AnalysisReportFactory.plateau.lead)
        XCTAssertEqual(report.cards, [
            .progression(
                exercise: "Squat (Barbell)",
                muscleGroup: .legs,
                fromKg: AnalysisReportFactory.plateauSquatKg,
                toKg: 105,
                reasoning: "Every session beat the 3-rep target by two — take the full step to 105 kg."
            ),
            .repProgression(
                exercise: "Lateral Raise (Dumbbell)",
                muscleGroup: .shoulders,
                weightKg: 10,
                fromReps: 12,
                toReps: 14,
                reasoning: "Twelve clean reps on the only dumbbell you log — earn the next one with reps."
            ),
            .note(title: "Bench Press (Barbell)", text: "Eight weeks at 60 kg — time to move on."),
            .note(title: "Seated Row (Cable)", text: "Rows rose every other week; keep going."),
        ])
    }

    /// Over the ceiling the step is a note, and a progress verdict with no
    /// card left behind it holds with the app's lead (#177, #233).
    func testPlateauRejectsAStepOverTheBandAndHolds() async throws {
        let outcome = try await run(.plateau, answer: AnalysisReportFactory.plateauOvershoot).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report.cards, [.note(title: "Squat (Barbell)", text: "A big jump, but the reps are there.")])
        XCTAssertEqual(report.verdict, .hold)
        XCTAssertEqual(report.headline, AnalysisReportValidator.holdHeadline)
        XCTAssertEqual(report.lead, AnalysisReportValidator.holdLead)
    }

    /// Two sessions a week: no recovery hint gets in the way of the cards.
    func testPlateauNeedsNoRecoveryAtAnyTimeOfDay() async throws {
        for now in [Self.morning, Self.evening] {
            let metrics = try await recoveryMetrics(for: .plateau, now: now)

            XCTAssertEqual(metrics.trainingDays, 2)
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
        // The model's lead argued for the load increase the app overruled, so
        // it gets the app's recovery lead (#170).
        XCTAssertEqual(report.lead, AnalysisReportValidator.recoveryLead(trainingDays: 6))
        XCTAssertNotEqual(report.lead, AnalysisReportFactory.overreached.lead)
        XCTAssertEqual(report.cards, [
            .recovery(
                reasoning: AnalysisReportValidator.insertedRecoveryReasoning,
                metrics: RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: 8.5)
            ),
            // The profile logs freely — no routine, no rep target — so the
            // 2-for-2 rule is not checkable and the load increase is a note
            // (ADR-013, #233), not a progression next to a recovery card.
            .note(title: "Bench Press (Barbell)", text: "Two sessions at 70 kg × 5 this week."),
        ])
    }

    // MARK: - Thin data (#170)

    /// A model that finds nothing to put on a card answers with none, and the
    /// screen gets a report — lead and summary — rather than the prose
    /// fallback. The disclosure then starts open.
    func testAThinAnswerStaysAReportWithoutCards() async throws {
        let outcome = try await run(.progressionReady, answer: AnalysisReportFactory.thin).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertTrue(report.cards.isEmpty)
        XCTAssertEqual(report.verdict, .hold)
        XCTAssertEqual(report.lead, AnalysisReportFactory.thin.lead)
        XCTAssertEqual(report.summary, AnalysisReportFactory.thin.summary)
        XCTAssertTrue(AnalysisFullAnalysis.startsExpanded(for: report.cards))
    }

    // MARK: - runner · endurance only (US-15 AC1, AC2, AC5)

    /// A window of nothing but running offers no choice and runs as
    /// "Endurance" — the implicit profile of US-15 AC1, with no picker on
    /// screen.
    func testTheRunnerOffersNoChoiceAndRunsAsEndurance() async throws {
        try await seed(.runner, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let run = try await analyse(answer: AnalysisReportFactory.runner(weeklyKilometers: kilometers))

        XCTAssertEqual(run.options.available, [.endurance])
        XCTAssertFalse(run.options.isChoice)
        XCTAssertEqual(run.options.preselected, .endurance)
        XCTAssertEqual(run.context?.analysisProfile, .endurance)
    }

    /// The endurance section of US-15 AC2, over a real cache: weekly distance
    /// and time, a mean heart rate that says how many sessions recorded one,
    /// the per-week table and the comparison with the four weeks before.
    func testTheRunnerPromptCarriesTheEnduranceSections() async throws {
        try await seed(.runner, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let prompt = try await analyse(
            answer: AnalysisReportFactory.runner(weeklyKilometers: kilometers)
        ).prompt

        XCTAssertTrue(prompt.contains("## Endurance, last 4 weeks ("), prompt)
        XCTAssertTrue(prompt.contains("## Endurance per week"), prompt)
        XCTAssertTrue(prompt.contains("## Previous 4 weeks "), prompt)
        XCTAssertTrue(prompt.contains("Total distance: "), prompt)
        XCTAssertTrue(prompt.contains("Total time: "), prompt)
        XCTAssertTrue(prompt.contains("Longest session"), prompt)
        XCTAssertTrue(prompt.contains("By sport:"), prompt)
        // Four of the sixteen runs wore no strap, so the mean has to say what
        // it rests on (US-15 AC7).
        XCTAssertTrue(prompt.contains("sessions that recorded one)"), prompt)
    }

    /// No strength section, and therefore no kilogram, on a window that holds
    /// no lifting — the mirror image of AC5 on the prompt side.
    func testTheRunnerPromptNamesNoStrengthWork() async throws {
        try await seed(.runner, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let prompt = try await analyse(
            answer: AnalysisReportFactory.runner(weeklyKilometers: kilometers)
        ).prompt

        XCTAssertFalse(prompt.contains("## Volume per week"), prompt)
        XCTAssertFalse(prompt.contains("## Exercises ("), prompt)
        XCTAssertFalse(prompt.contains("## Muscle groups"), prompt)
        XCTAssertFalse(prompt.contains(" kg"), prompt)
    }

    /// US-15 AC5: the result is a metric card in kilometres, anchored on the
    /// week the cache holds, and nothing on it is a weight.
    func testTheRunnerResultIsAMetricCardInEnduranceUnits() async throws {
        try await seed(.runner, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let outcome = try await analyse(
            answer: AnalysisReportFactory.runner(weeklyKilometers: kilometers)
        ).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report.verdict, .progress)
        XCTAssertEqual(report.cards.count, 1)
        XCTAssertEqual(report.cards.first?.kind, .metric)
        guard case let .metric(_, from, to, unit, _, source)? = report.cards.first else {
            return XCTFail("The endurance answer did not survive as a metric card")
        }
        XCTAssertEqual(unit, .kilometers)
        XCTAssertEqual(from, kilometers, accuracy: 0.0001)
        XCTAssertEqual(to, AnalysisReportFactory.metricStep(from: kilometers), accuracy: 0.0001)
        XCTAssertEqual(source, "Run")
    }

    /// The context line of a single endurance source, and no thin-data
    /// warning: sixteen runs in the window is a basis (US-15 AC4).
    func testTheRunnerBasisNamesStravaAlone() async throws {
        try await seed(.runner, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let run = try await analyse(answer: AnalysisReportFactory.runner(weeklyKilometers: kilometers))
        let context = try XCTUnwrap(run.context)

        XCTAssertEqual(context.countedSources, [.strava])
        XCTAssertEqual(context.sessionCount(from: .strava), 16)
        XCTAssertEqual(context.basisDescription, "16 Strava sessions")
        XCTAssertEqual(context.analysedCounts, [.endurance: 16])
        XCTAssertFalse(context.isThin)
        XCTAssertNil(context.thinDataWarning)
    }

    // MARK: - mixed · both domains (US-15 AC1, AC2, AC4)

    /// Two domains in the window, so all three profiles are offered and
    /// "Overall load" is the default (US-15 AC1).
    func testTheMixedWindowOffersAllThreeProfiles() async throws {
        try await seed(.mixed, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let run = try await analyse(
            answer: AnalysisReportFactory.mixedOverallLoad(weeklyKilometers: kilometers)
        )

        XCTAssertEqual(run.options.available, [.strength, .endurance, .overallLoad])
        XCTAssertTrue(run.options.isChoice)
        XCTAssertEqual(run.options.preselected, .overallLoad)
        XCTAssertEqual(run.context?.analysisProfile, .overallLoad)
    }

    /// US-15 AC2 end to end: a strength section, an endurance section and a
    /// week-structure section naming the two overlap days the fixture was
    /// built around.
    func testTheMixedPromptCarriesAllThreeSections() async throws {
        try await seed(.mixed, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let prompt = try await analyse(
            answer: AnalysisReportFactory.mixedOverallLoad(weeklyKilometers: kilometers)
        ).prompt

        XCTAssertTrue(prompt.contains("## Volume per week"), prompt)
        XCTAssertTrue(prompt.contains("## Exercises (last 4 weeks)"), prompt)
        XCTAssertTrue(prompt.contains("## Endurance, last 4 weeks ("), prompt)
        XCTAssertTrue(prompt.contains("## Week structure (last 4 weeks)"), prompt)
        XCTAssertTrue(prompt.contains("Days with both: 8"), prompt)
        XCTAssertTrue(prompt.contains("Days with strength only: 4"), prompt)
        XCTAssertTrue(prompt.contains("Days with endurance only: 4"), prompt)
        XCTAssertTrue(prompt.contains("Last 7 days: "), prompt)
    }

    /// US-15 AC4: the line counts per source, and a window with twelve of
    /// each is not thin in either domain.
    func testTheMixedBasisCountsBothSources() async throws {
        try await seed(.mixed, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let run = try await analyse(
            answer: AnalysisReportFactory.mixedOverallLoad(weeklyKilometers: kilometers)
        )
        let context = try XCTUnwrap(run.context)

        XCTAssertEqual(context.basisDescription, "12 Hevy · 12 Strava sessions")
        XCTAssertEqual(context.domainCounts, [.strength: 12, .endurance: 12])
        XCTAssertEqual(context.analysedCounts, [.strength: 12, .endurance: 12])
        XCTAssertFalse(context.isThin)
    }

    /// Design 3.4d over a real cache: the interference card carries the app's
    /// own day counts, not the ones the model guessed, and the metric card
    /// under it is anchored on the app's week (#186).
    func testTheMixedResultLeadsWithTheInterferenceCard() async throws {
        try await seed(.mixed, now: Self.morning)
        let kilometers = try await weeklyFigure(.kilometers)

        let outcome = try await analyse(
            answer: AnalysisReportFactory.mixedOverallLoad(weeklyKilometers: kilometers)
        ).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report.cards.map(\.kind), [.interference, .metric])
        guard case let .interference(metrics, _)? = report.cards.first else {
            return XCTFail("The interference card did not survive")
        }
        XCTAssertEqual(metrics, InterferenceMetrics(strengthDays: 3, cardioDays: 3, overlapDays: 2))
    }

    /// Under "Strength" the endurance sessions are counted on the line — the
    /// user logged them — and deliberately left out of the analysis. The
    /// prompt says so, and the thin-data rule stays silent about a domain this
    /// run was never about (US-15 AC4, #185).
    func testTheMixedWindowUnderStrengthStatesWhatItLeftOut() async throws {
        try await seed(.mixed, now: Self.morning)
        // The week's distance as the *whole* week recorded it — under
        // "Strength" the app has no such figure at all, which is exactly why
        // the card built on it must not survive.
        let kilometers = try await weeklyFigure(.kilometers)

        let run = try await analyse(
            answer: AnalysisReportFactory.runner(weeklyKilometers: kilometers),
            choosing: .strength
        )

        XCTAssertTrue(run.prompt.contains("Analyse my strength training only"), run.prompt)
        XCTAssertTrue(run.prompt.contains("I asked about my strength training only"), run.prompt)
        XCTAssertFalse(run.prompt.contains("## Endurance, last 4 weeks ("), run.prompt)

        let context = try XCTUnwrap(run.context)
        XCTAssertEqual(context.analysisProfile, .strength)
        XCTAssertEqual(context.basisDescription, "12 Hevy · 12 Strava sessions")
        XCTAssertEqual(context.analysedCounts, [.strength: 12])
        XCTAssertTrue(context.thinDomains.isEmpty)

        // A card in kilometres has no place under "Strength" (US-15 AC5): it
        // is downgraded rather than shown.
        let report = try XCTUnwrap(run.outcome?.report)
        XCTAssertFalse(report.cards.contains { $0.kind == .metric })
    }

    /// The mirror image of the case above (US-15 AC5, #185): the same window
    /// of twelve lifts and twelve runs, analysed under "Endurance". The
    /// lifting half is counted on the line and left out of the analysis, so
    /// the prompt carries no strength section and not a single kilogram — and
    /// a progression card, which is a load in kilograms by construction, is
    /// downgraded to a note rather than shown.
    func testTheMixedWindowUnderEnduranceStatesWhatItLeftOut() async throws {
        try await seed(.mixed, now: Self.morning)

        let run = try await analyse(
            answer: AnalysisReportFactory.progressionReady,
            choosing: .endurance
        )

        XCTAssertTrue(run.prompt.contains("Analyse my endurance training only"), run.prompt)
        XCTAssertTrue(run.prompt.contains("I asked about my endurance training only"), run.prompt)
        XCTAssertTrue(run.prompt.contains("## Endurance, last 4 weeks ("), run.prompt)
        XCTAssertFalse(run.prompt.contains("## Volume per week"), run.prompt)
        XCTAssertFalse(run.prompt.contains("## Exercises"), run.prompt)
        XCTAssertFalse(run.prompt.contains("kg"), run.prompt)

        let context = try XCTUnwrap(run.context)
        XCTAssertEqual(context.analysisProfile, .endurance)
        XCTAssertEqual(context.basisDescription, "12 Hevy · 12 Strava sessions")
        XCTAssertEqual(context.analysedCounts, [.endurance: 12])
        XCTAssertTrue(context.thinDomains.isEmpty)

        // A load in kilograms has no place under "Endurance" (US-15 AC5): the
        // card keeps the model's sentence as a note and loses its figures.
        let report = try XCTUnwrap(run.outcome?.report)
        XCTAssertFalse(report.cards.contains { $0.kind == .progression })
        XCTAssertEqual(report.cards.map(\.kind), [.note])
    }

    /// The per-domain thin-data warning of US-15 AC4: a full lifting window
    /// next to an endurance half that has only just started warns about the
    /// endurance half by name, and says nothing about the strength one.
    func testAMixedWindowWithAThinEnduranceHalfWarnsAboutThatHalf() async throws {
        try await seed(.mixed, now: Self.morning, enduranceSessions: 3)
        let kilometers = try await weeklyFigure(.kilometers)

        let run = try await analyse(
            answer: AnalysisReportFactory.mixedOverallLoad(weeklyKilometers: kilometers)
        )
        let context = try XCTUnwrap(run.context)

        XCTAssertEqual(context.basisDescription, "12 Hevy · 3 Strava sessions")
        XCTAssertEqual(context.analysedCounts, [.strength: 12, .endurance: 3])
        XCTAssertTrue(context.isThin)
        XCTAssertEqual(context.thinDomains, [.endurance])
        XCTAssertEqual(
            context.thinDataWarning,
            "Thin endurance data — 3 sessions. Treat the recommendation as a starting point."
        )
    }

    // MARK: - overreached-mixed · recovery across sources (US-15 AC3)

    /// US-15 AC3: six of the last seven days, spread over three sources, force
    /// the recovery card and the verdict — although no single source reaches
    /// the threshold and the model's answer carried no card at all.
    func testTheOverreachedMixedWeekForcesTheRecoveryCard() async throws {
        let outcome = try await run(.overreachedMixed, answer: AnalysisReportFactory.thin).outcome

        let report = try XCTUnwrap(outcome?.report)
        XCTAssertEqual(report.verdict, .recover)
        XCTAssertEqual(report.headline, AnalysisReportValidator.recoveryHeadline)
        XCTAssertEqual(report.lead, AnalysisReportValidator.recoveryLead(trainingDays: 6))
        XCTAssertEqual(report.cards.count, 1)
        guard case let .recovery(_, metrics)? = report.cards.first else {
            return XCTFail("No recovery card was inserted")
        }
        XCTAssertEqual(metrics.trainingDays, 6)
        XCTAssertEqual(metrics.sessions, 6)
        XCTAssertEqual(metrics.suggestedRestHours, 48)
        XCTAssertEqual(try XCTUnwrap(metrics.averageRPE), 8.5, accuracy: 0.0001)
        XCTAssertNotNil(metrics.averageHeartRate)
    }

    /// The same week's prompt states the cross-source day count the app then
    /// overrules the model on (#184).
    func testTheOverreachedMixedPromptStatesTheSixDayWeek() async throws {
        let prompt = try await run(.overreachedMixed, answer: AnalysisReportFactory.thin).prompt

        XCTAssertTrue(prompt.contains("## Week structure (last 4 weeks)"), prompt)
        XCTAssertTrue(prompt.contains("Last 7 days: 6 training days"), prompt)
    }

    /// Three sources on one line, in a fixed order (US-15 AC4).
    func testTheOverreachedMixedBasisNamesThreeSources() async throws {
        let finished = try await run(.overreachedMixed, answer: AnalysisReportFactory.thin)
        let context = try XCTUnwrap(finished.context)

        XCTAssertEqual(context.countedSources, [.hevy, .strava, .polar])
        XCTAssertEqual(context.basisDescription, "11 Hevy · 5 Strava · 3 Polar sessions")
        XCTAssertFalse(context.isThin)
    }

    // MARK: - Helpers

    /// Caches `profile` as of `now` and runs one analysis that `answer`
    /// completes.
    private func run(
        _ profile: MockWorkoutProfile,
        answer: AnalysisReport,
        now: Date = AnalysisMockProfileTests.morning
    ) async throws -> Run {
        try await seed(profile, now: now)
        return try await analyse(answer: answer, now: now)
    }

    /// One analysis over whatever is already cached, the way the screen runs
    /// it: the intro's profile read, an optional tap on the picker, then the
    /// run (#188).
    ///
    /// Separate from `run(_:answer:now:)` because a metric card has to be
    /// anchored on the app's own weekly figure, which is only knowable once
    /// the cache holds the window — the answer is therefore built between the
    /// seeding and the run.
    private func analyse(
        answer: AnalysisReport,
        choosing analysisProfile: AnalysisProfile? = nil,
        now: Date = AnalysisMockProfileTests.morning
    ) async throws -> Run {
        await streamer.setReport(answer)
        let sut = AnalysisViewModel(
            cache: store,
            exerciseCache: store,
            detailCache: store,
            inference: streamer,
            analysisProfiles: AnalysisProfileStore(defaults: defaults),
            calendar: Self.calendar,
            now: { now }
        )

        await sut.prepareProfileSelection()
        if let analysisProfile {
            await sut.select(analysisProfile)
        }
        await sut.start()

        let userPrompt = await streamer.userPrompt
        let prompt = try XCTUnwrap(userPrompt, "The analysis never reached the provider")
        return Run(
            prompt: prompt,
            outcome: sut.state.outcome,
            context: sut.context,
            options: sut.profileOptions
        )
    }

    /// What one analysis produced — the prompt that went out, the cards that
    /// came back, the basis the screen names and the picker the intro showed.
    private struct Run {
        let prompt: String
        let outcome: AnalysisOutcome?
        let context: AnalysisContext?
        let options: AnalysisProfileOptions
    }

    /// The app's own weekly figure for `unit` over the cached week — what a
    /// metric card's `from` has to be (#186).
    private func weeklyFigure(
        _ unit: MetricUnit,
        now: Date = AnalysisMockProfileTests.morning,
        analysisProfile: AnalysisProfile = .overallLoad
    ) async throws -> Double {
        let summaries = try await store.workoutSummaries(since: .distantPast)
        let metrics = AnalysisReportEvidence.weeklyMetrics(
            in: summaries,
            now: now,
            calendar: Self.calendar,
            analysisProfile: analysisProfile
        )
        return try XCTUnwrap(metrics[unit], "The week recorded no \(unit.rawValue)")
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

    /// Caches the profile the way `MockDataSeeder` does: one source at a time,
    /// through the real mapping.
    ///
    /// - Parameter enduranceSessions: Caps how many sessions each endurance
    ///   source contributes, newest first. For the one case the fixtures
    ///   cannot hold on their own — a mixed week whose endurance half has only
    ///   just started, which is what the per-domain thin-data warning of
    ///   US-15 AC4 is about.
    private func seed(
        _ profile: MockWorkoutProfile,
        now: Date,
        enduranceSessions: Int? = nil
    ) async throws {
        let loader = MockWorkoutLoader(now: { now })
        for payload in profile.payloads {
            var activities = try loader.activities(for: profile, from: payload.source)
            if let enduranceSessions, payload.source.isEnduranceSource {
                activities = Array(activities.prefix(enduranceSessions))
            }
            try await store.replaceCachedWorkouts(from: payload.source, with: activities)
        }
    }

    private func row(startingWith prefix: String, in prompt: String) throws -> String {
        try XCTUnwrap(
            prompt.split(separator: "\n").map(String.init).first { $0.hasPrefix(prefix) },
            "No prompt line starts with \"\(prefix)\""
        )
    }
}

#endif

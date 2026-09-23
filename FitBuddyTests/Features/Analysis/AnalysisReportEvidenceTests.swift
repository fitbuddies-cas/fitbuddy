import XCTest
@testable import FitBuddy

/// `AnalysisReportEvidence` (#175): gathered from the same reads as the
/// prompt, so the validator checks a card against the figures the model saw.
final class AnalysisReportEvidenceTests: XCTestCase {
    private var calendar: Calendar!
    /// 2025-06-15 12:26:40 UTC.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    }

    /// The working weight the evidence holds is the one the prompt line names
    /// — here from the latest session with working sets, not the warm-up-only
    /// one after it.
    func testListedExercisesCarryTheWeightThePromptNames() {
        let bench = exercise("Bench Press", volume: 3_000)
        let progressions = [bench.id: ExerciseProgression(id: bench.id, title: bench.title, sessions: [
            session(daysAgo: 9, sets: [set(0, .normal, 57.5, 5)]),
            session(daysAgo: 5, sets: [set(0, .normal, 60, 5), set(1, .normal, 60, 6)]),
            session(daysAgo: 2, sets: [set(0, .warmup, 40, 10)]),
        ])]

        let prompt = AnalysisPromptBuilder.make(
            summaries: [summary(daysAgo: 2)],
            exercises: [bench],
            progressions: progressions,
            now: reference,
            calendar: calendar
        )
        let evidence = makeEvidence(summaries: [summary(daysAgo: 2)], exercises: [bench], progressions: progressions)

        XCTAssertTrue(prompt.user.contains("- Bench Press: 60 kg × 6"))
        // The step and the 2-for-2 verdict as well: the range a card is
        // checked against is derived from exactly these (#233).
        XCTAssertTrue(prompt.user.contains("No rep target on file. Next: progress reps, not weight."))
        XCTAssertEqual(evidence.exercises, [
            ListedExercise(
                title: "Bench Press",
                muscleGroup: .chest,
                workingSet: WorkingSet(weightKg: 60, reps: 6),
                smallestStepKg: 2.5,
                twoForTwo: .notCheckable
            ),
        ])
    }

    /// A dumbbell step below the barbell step reaches the evidence as the
    /// prompt line names it: 2 kg, not the 2.5 kg floor.
    func testListedStepEqualsThePromptLine() {
        let raise = exercise("Lateral Raise (Dumbbell)", volume: 1_000)
        let progressions = [raise.id: ExerciseProgression(id: raise.id, title: raise.title, sessions: [
            session(daysAgo: 9, sets: [set(0, .normal, 8, 12)]),
            session(daysAgo: 2, sets: [set(0, .normal, 10, 12)]),
        ])]

        let prompt = AnalysisPromptBuilder.make(
            summaries: [summary(daysAgo: 2)],
            exercises: [raise],
            progressions: progressions,
            now: reference,
            calendar: calendar
        )
        let evidence = makeEvidence(summaries: [summary(daysAgo: 2)], exercises: [raise], progressions: progressions)

        XCTAssertEqual(evidence.exercises.map(\.smallestStepKg), [2])
        XCTAssertEqual(ProgressionBand.range(for: evidence.exercises[0]), 12...12)
    }

    /// Only what the prompt lists: past the cap, without a progression, or
    /// without a session in the window, an exercise has no line and no entry.
    func testOnlyExercisesWithAPromptLineAreListed() {
        let listed = exercise("Squat", volume: 5_000)
        let noProgression = exercise("Deadlift", volume: 4_000)
        let outsideWindow = exercise("Overhead Press", volume: 3_000)
        let progressions = [
            listed.id: ExerciseProgression(id: listed.id, title: listed.title, sessions: [
                session(daysAgo: 3, sets: [set(0, .normal, 80, 5)]),
            ]),
            outsideWindow.id: ExerciseProgression(id: outsideWindow.id, title: outsideWindow.title, sessions: [
                session(daysAgo: 40, sets: [set(0, .normal, 40, 5)]),
            ]),
        ]

        let evidence = makeEvidence(
            summaries: [summary(daysAgo: 3)],
            exercises: [listed, noProgression, outsideWindow],
            progressions: progressions
        )

        XCTAssertEqual(evidence.exercises.map(\.title), ["Squat"])
    }

    /// No step in the line, no step in the evidence: a single logged weight,
    /// and a gap past the share and the floor (8 → 12 kg), both leave it `nil`.
    func testAnExerciseWithoutAListedStepCarriesNone() {
        let raise = exercise("Lateral Raise (Dumbbell)", volume: 1_000)
        let row = exercise("Row", volume: 900)
        let progressions = [
            raise.id: ExerciseProgression(id: raise.id, title: raise.title, sessions: [
                session(daysAgo: 9, sets: [set(0, .normal, 8, 15)]),
                session(daysAgo: 2, sets: [set(0, .normal, 12, 10)]),
            ]),
            row.id: ExerciseProgression(id: row.id, title: row.title, sessions: [
                session(daysAgo: 3, sets: [set(0, .normal, 50, 10)]),
            ]),
        ]

        let evidence = makeEvidence(summaries: [summary(daysAgo: 2)], exercises: [raise, row], progressions: progressions)

        XCTAssertEqual(evidence.exercises.map(\.title), ["Lateral Raise (Dumbbell)", "Row"])
        XCTAssertEqual(evidence.exercises.map(\.smallestStepKg), [nil, nil])
    }

    /// The per-week figure equals the one the prompt's Muscle groups section
    /// states, over the analysed window's strength sessions only.
    func testMuscleGroupFrequenciesMatchThePrompt() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let legs = MuscleLoad(group: .legs, volumeKg: 2_000, setCount: 3)
        let summaries = [
            summary(daysAgo: 1, loads: [chest, legs]),
            summary(daysAgo: 4, loads: [chest]),
            summary(daysAgo: 8, loads: [chest]),
            summary(daysAgo: 40, loads: [legs]),
        ]

        let prompt = AnalysisPromptBuilder.make(summaries: summaries, now: reference, calendar: calendar)
        let evidence = makeEvidence(summaries: summaries)

        XCTAssertEqual(evidence.muscleGroupsPerWeek, [.chest: 0.8, .legs: 0.3])
        XCTAssertTrue(prompt.user.contains("Chest: 3000 kg (60% of volume), 9 working sets, trained in 3 sessions (0.8 per week)"))
        XCTAssertTrue(prompt.user.contains("Legs: 2000 kg (40% of volume), 3 working sets, trained in 1 session (0.3 per week)"))
    }

    func testRecoveryIsGatheredFromTheLastSevenDays() {
        let summaries = (0..<6).map { summary(daysAgo: $0, id: "w\($0)") }

        let evidence = makeEvidence(summaries: summaries)

        XCTAssertEqual(evidence.recovery, RecoveryMetrics(sessions: 6, trainingDays: 6, averageRPE: nil))
    }

    /// The two halves of the evidence read different sets since #184: the
    /// muscle-group frequency stays strength-only — a run loads no muscle group
    /// the prompt states a frequency for — while the recovery metrics count
    /// every session of the week (US-15 AC3).
    func testRecoveryCountsCardioWhileTheMuscleFrequenciesDoNot() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let summaries = [
            summary(daysAgo: 0, id: "h0", loads: [chest]),
            summary(daysAgo: 1, id: "h1", loads: [chest]),
            summary(daysAgo: 2, id: "h2", loads: [chest]),
            run(daysAgo: 3, id: "s0", heartRate: 150),
            run(daysAgo: 4, id: "s1", heartRate: 160),
            run(daysAgo: 5, id: "s2"),
        ]

        let evidence = makeEvidence(summaries: summaries)

        XCTAssertEqual(evidence.recovery.sessions, 6)
        XCTAssertEqual(evidence.recovery.trainingDays, 6)
        XCTAssertTrue(evidence.recovery.needsRecovery)
        XCTAssertEqual(evidence.recovery.averageHeartRate, 155)
        XCTAssertEqual(evidence.muscleGroupsPerWeek, [.chest: 0.8])
    }

    // MARK: - Weekly metrics and interference (#186)

    /// The anchors a metric card's `from` is checked against: one figure per
    /// unit, over the last seven days, whatever filled them.
    func testTheWeeklyMetricsCoverEveryUnitTheWeekRecorded() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let evidence = makeEvidence(summaries: [
            summary(daysAgo: 1, id: "h0", loads: [chest]),
            summary(daysAgo: 2, id: "h1", loads: [chest]),
            run(daysAgo: 1, id: "s0", heartRate: 150),
            run(daysAgo: 3, id: "s1", heartRate: 160),
        ])

        // Two 1 000 kg sessions, two 8 km runs of 40 min each.
        XCTAssertEqual(evidence.weeklyMetrics[.kilograms], 2_000)
        XCTAssertEqual(try XCTUnwrap(evidence.weeklyMetrics[.kilometers]), 16, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(evidence.weeklyMetrics[.hours]), 80.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(evidence.weeklyMetrics[.beatsPerMinute], 155)
        XCTAssertEqual(try XCTUnwrap(evidence.weeklyMetrics[.minutesPerKilometer]), 5, accuracy: 0.0001)
    }

    /// A unit nothing recorded is absent rather than zero: there is nothing to
    /// check a card against, and the validator turns it into a note instead of
    /// drawing a step from nowhere (US-15 AC7).
    func testAUnitTheWeekDidNotRecordIsAbsent() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let evidence = makeEvidence(summaries: [summary(daysAgo: 1, id: "h0", loads: [chest])])

        XCTAssertEqual(evidence.weeklyMetrics[.kilograms], 1_000)
        XCTAssertNil(evidence.weeklyMetrics[.kilometers])
        XCTAssertNil(evidence.weeklyMetrics[.minutesPerKilometer])
        XCTAssertNil(evidence.weeklyMetrics[.beatsPerMinute])
    }

    /// The pace is taken over the sessions that recorded both a distance and a
    /// time — the rule `EndurancePromptSection` settled on, for the same
    /// reason: a treadmill session with no distance would otherwise slow the
    /// whole week's pace down.
    func testThePaceIgnoresSessionsWithoutBothFigures() throws {
        let timeOnly = WorkoutSummary(
            id: "treadmill",
            title: "Treadmill",
            startTime: start(daysAgo: 2),
            source: .hevy,
            kind: .strength,
            volumeKg: 0,
            exerciseCount: 1,
            countedSetCount: 1,
            durationSeconds: 3_600
        )
        let evidence = makeEvidence(summaries: [run(daysAgo: 1, id: "s0"), timeOnly])

        XCTAssertEqual(try XCTUnwrap(evidence.weeklyMetrics[.minutesPerKilometer]), 5, accuracy: 0.0001)
    }

    /// Sessions the window holds but the week does not are not part of the
    /// anchor: the card is about the last seven days.
    func testTheWeeklyMetricsStopAtSevenDays() {
        let evidence = makeEvidence(summaries: [run(daysAgo: 1, id: "s0"), run(daysAgo: 8, id: "s1")])

        XCTAssertEqual(try XCTUnwrap(evidence.weeklyMetrics[.kilometers]), 8, accuracy: 0.0001)
    }

    /// The interference counts come from the same seven days, so the report
    /// cannot cite two different weeks.
    func testTheInterferenceCountsComeFromTheSameWeek() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let evidence = makeEvidence(summaries: [
            summary(daysAgo: 1, id: "h0", loads: [chest]),
            run(daysAgo: 1, id: "s0"),
            run(daysAgo: 3, id: "s1"),
        ])

        XCTAssertEqual(evidence.interference.strengthDays, 1)
        XCTAssertEqual(evidence.interference.cardioDays, 2)
        XCTAssertEqual(evidence.interference.overlapDays, 1)
    }

    /// Review finding 2: one run and one ride in the same week used to divide
    /// 38 km by 100 min and call it a pace — 2:38 /km, which neither of them
    /// ran. The anchor now covers only the sports read in minutes per
    /// kilometre, which leaves the run's own 5:00.
    func testThePaceIgnoresSportsThatAreNotReadPerKilometre() throws {
        let evidence = makeEvidence(summaries: [run(daysAgo: 1, id: "s0"), ride(daysAgo: 2, id: "s1")])

        XCTAssertEqual(try XCTUnwrap(evidence.weeklyMetrics[.minutesPerKilometer]), 5, accuracy: 0.0001)
        // The distance and time anchors still cover the whole week: they are
        // sums, and a sum over both sports is true.
        XCTAssertEqual(try XCTUnwrap(evidence.weeklyMetrics[.kilometers]), 38, accuracy: 0.0001)
    }

    /// A week of rides alone has no pace anchor at all, so a pace card over it
    /// is downgraded rather than checked against a figure nobody ran.
    func testAWeekOfRidesHasNoPaceAnchor() {
        XCTAssertNil(makeEvidence(summaries: [ride(daysAgo: 1, id: "s0")]).weeklyMetrics[.minutesPerKilometer])
    }

    // MARK: - Profile-covered anchors (#186 review finding 4)

    /// An anchor may only come from training this analysis looked at. Under
    /// "Strength" the runs are excluded, so the hours and the heart rate of a
    /// mixed week cannot be printed on a screen that says the running was left
    /// out.
    func testTheAnchorsCoverOnlyTheDomainsTheProfileAnalyses() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let summaries = [
            summary(daysAgo: 1, id: "h0", loads: [chest]),
            run(daysAgo: 2, id: "s0", heartRate: 150),
        ]

        let strength = makeEvidence(summaries: summaries, analysisProfile: .strength)

        XCTAssertEqual(strength.weeklyMetrics[.kilograms], 1_000)
        XCTAssertNil(strength.weeklyMetrics[.kilometers], "the run's distance is not this analysis's")
        XCTAssertNil(strength.weeklyMetrics[.hours], "a barbell session records no set duration")
        XCTAssertNil(strength.weeklyMetrics[.beatsPerMinute], "the only heart rate came from the run")
        XCTAssertNil(strength.weeklyMetrics[.minutesPerKilometer])
    }

    /// The mirror image, and the case that shows the filter is on the sessions
    /// rather than on the unit: under "Endurance" the volume is gone and the
    /// endurance figures remain.
    func testTheEnduranceProfileKeepsOnlyTheEnduranceAnchors() throws {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let summaries = [
            summary(daysAgo: 1, id: "h0", loads: [chest]),
            run(daysAgo: 2, id: "s0", heartRate: 150),
        ]

        let endurance = makeEvidence(summaries: summaries, analysisProfile: .endurance)

        XCTAssertNil(endurance.weeklyMetrics[.kilograms])
        XCTAssertEqual(try XCTUnwrap(endurance.weeklyMetrics[.kilometers]), 8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(endurance.weeklyMetrics[.hours]), 40.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(endurance.weeklyMetrics[.beatsPerMinute], 150)
    }

    /// "Overall load" covers both, i.e. the behaviour before the filter.
    func testOverallLoadAnchorsOnTheWholeWeek() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let evidence = makeEvidence(summaries: [
            summary(daysAgo: 1, id: "h0", loads: [chest]),
            run(daysAgo: 2, id: "s0", heartRate: 150),
        ])

        XCTAssertEqual(evidence.weeklyMetrics[.kilograms], 1_000)
        XCTAssertNotNil(evidence.weeklyMetrics[.kilometers])
        XCTAssertEqual(evidence.weeklyMetrics[.beatsPerMinute], 150)
    }

    /// `hours` is the time the sessions **recorded**, not the time they
    /// lasted: `WorkoutSummary.durationSeconds` sums the counted sets, so an
    /// ordinary barbell week has no figure in the unit at all (review
    /// finding 6).
    func testTheHoursAnchorIsTheRecordedTimeNotTheSessionLength() {
        let chest = MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 3)
        let evidence = makeEvidence(summaries: [summary(daysAgo: 1, id: "h0", loads: [chest])])

        XCTAssertEqual(evidence.weeklyMetrics[.kilograms], 1_000)
        XCTAssertNil(evidence.weeklyMetrics[.hours])
    }

    // MARK: - Helpers

    private func makeEvidence(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary] = [],
        progressions: [String: ExerciseProgression] = [:],
        analysisProfile: AnalysisProfile = .overallLoad
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(
            summaries: summaries,
            exercises: exercises,
            progressions: progressions,
            details: [],
            window: .default,
            now: reference,
            calendar: calendar,
            analysisProfile: analysisProfile
        )
    }

    private func ride(daysAgo: Int, id: String) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: "Evening Ride",
            startTime: start(daysAgo: daysAgo),
            source: .strava,
            kind: .ride,
            volumeKg: 0,
            exerciseCount: 1,
            countedSetCount: 1,
            distanceMeters: 30_000,
            durationSeconds: 3_600
        )
    }

    private func start(daysAgo: Int) -> Date {
        calendar.startOfDay(for: reference).addingTimeInterval(Double(-daysAgo) * 86_400 + 43_200)
    }

    private func run(daysAgo: Int, id: String, heartRate: Int? = nil) -> WorkoutSummary {
        WorkoutSummary(
            id: id,
            title: "Morning Run",
            startTime: start(daysAgo: daysAgo),
            source: .strava,
            kind: .run,
            volumeKg: 0,
            exerciseCount: 1,
            countedSetCount: 1,
            distanceMeters: 8_000,
            durationSeconds: 2_400,
            cardio: heartRate.map { CardioMetrics(averageHeartRate: $0) }
        )
    }

    private func summary(daysAgo: Int, id: String? = nil, loads: [MuscleLoad] = []) -> WorkoutSummary {
        WorkoutSummary(
            id: id ?? "w-\(daysAgo)",
            title: "Session",
            startTime: start(daysAgo: daysAgo),
            volumeKg: loads.reduce(0) { $0 + $1.volumeKg },
            exerciseCount: loads.count,
            countedSetCount: loads.reduce(0) { $0 + $1.setCount },
            muscleLoads: loads
        )
    }

    private func exercise(_ title: String, volume: Double) -> ExerciseSummary {
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

    private func session(daysAgo: Int, sets: [SetDetail]) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(workoutID: "w-\(daysAgo)", sessionStart: start(daysAgo: daysAgo), sets: sets)
    }

    private func set(_ index: Int, _ type: SetType, _ weightKg: Double, _ reps: Int) -> SetDetail {
        SetDetail(index: index, type: type, weightKg: weightKg, reps: reps, distanceMeters: nil, durationSeconds: nil, rpe: nil)
    }
}

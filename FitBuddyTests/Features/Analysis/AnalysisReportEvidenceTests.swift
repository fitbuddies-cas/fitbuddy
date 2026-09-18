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
        // The step as well: the validator caps a card at the step the line names.
        XCTAssertTrue(prompt.user.contains("Smallest logged step: 2.5 kg."))
        XCTAssertEqual(evidence.exercises, [
            ListedExercise(
                title: "Bench Press",
                muscleGroup: .chest,
                workingSet: WorkingSet(weightKg: 60, reps: 6),
                smallestStepKg: 2.5
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

        XCTAssertTrue(prompt.user.contains("Smallest logged step: 2 kg."))
        XCTAssertEqual(evidence.exercises.map(\.smallestStepKg), [2])
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

    // MARK: - Helpers

    private func makeEvidence(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary] = [],
        progressions: [String: ExerciseProgression] = [:]
    ) -> AnalysisReportEvidence {
        AnalysisReportEvidence(
            summaries: summaries,
            exercises: exercises,
            progressions: progressions,
            details: [],
            window: .default,
            now: reference,
            calendar: calendar
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

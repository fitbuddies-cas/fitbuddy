import XCTest
@testable import FitBuddy

/// The per-workout muscle split that feeds the dashboard's distribution chart
/// (#27). Built straight from unattached models — the reduction needs no
/// SwiftData container.
final class WorkoutSummaryMuscleLoadTests: XCTestCase {
    func testSplitsVolumeByMuscleGroup() {
        let summary = WorkoutSummary(workout: workout(exercises: [
            ("Bench Press (Barbell)", [(SetType.normal, 100.0, 10)]),
            ("Squat (Barbell)", [(SetType.normal, 120.0, 5)]),
        ]))

        XCTAssertEqual(summary.muscleLoads, [
            MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 1),
            MuscleLoad(group: .legs, volumeKg: 600, setCount: 1),
        ])
    }

    func testMergesExercisesThatLoadTheSameGroup() {
        let summary = WorkoutSummary(workout: workout(exercises: [
            ("Bench Press (Barbell)", [(SetType.normal, 100.0, 10)]),
            ("Chest Fly (Machine)", [(SetType.normal, 40.0, 12)]),
        ]))

        XCTAssertEqual(summary.muscleLoads, [
            MuscleLoad(group: .chest, volumeKg: 1_480, setCount: 2),
        ])
    }

    /// Warm-ups are excluded from volume everywhere, so they must not inflate
    /// a group's share either.
    func testWarmupSetsStayOutOfTheSplit() {
        let summary = WorkoutSummary(workout: workout(exercises: [
            ("Bench Press (Barbell)", [(SetType.warmup, 60.0, 10), (SetType.normal, 100.0, 10)]),
        ]))

        XCTAssertEqual(summary.muscleLoads, [
            MuscleLoad(group: .chest, volumeKg: 1_000, setCount: 1),
        ])
    }

    /// A bodyweight movement has sets but no kg volume — the group is still
    /// part of the split, carrying its set count.
    func testBodyweightWorkKeepsItsSetsWithoutVolume() {
        let summary = WorkoutSummary(workout: workout(exercises: [
            ("Pull Up", [(SetType.normal, nil, 8), (SetType.normal, nil, 6)]),
        ]))

        XCTAssertEqual(summary.muscleLoads, [
            MuscleLoad(group: .back, volumeKg: 0, setCount: 2),
        ])
    }

    // MARK: - Strava sessions (#144)

    /// A Strava activity is one whole-body effort: it stays out of the muscle
    /// split, which remains Hevy's strength picture (US-5 AC1).
    func testStravaSessionsStayOutOfTheSplit() {
        let summary = WorkoutSummary(workout: stravaRun(distance: 5_000, movingTime: 1_800))

        XCTAssertEqual(summary.muscleLoads, [])
        XCTAssertEqual(summary.source, .strava)
        XCTAssertEqual(summary.countedSetCount, 1)
    }

    func testPolarSessionsStayOutOfTheSplit() {
        let summary = WorkoutSummary(workout: stravaRun(distance: 5_000, movingTime: 1_800, source: .polar))

        XCTAssertEqual(summary.muscleLoads, [])
        XCTAssertEqual(summary.source, .polar)
    }

    /// The figures a cardio row shows instead of kg.
    func testCardioTotalsAreSummedOverTheCountedSets() {
        let summary = WorkoutSummary(workout: stravaRun(distance: 5_000, movingTime: 1_800))

        XCTAssertEqual(summary.volumeKg, 0)
        XCTAssertEqual(summary.distanceMeters, 5_000)
        XCTAssertEqual(summary.durationSeconds, 1_800)
        XCTAssertTrue(summary.isCardio)
    }

    func testAStrengthSessionHasNoCardioTotalsAndIsNotCardio() {
        let summary = WorkoutSummary(workout: workout(exercises: [
            ("Bench Press (Barbell)", [(SetType.normal, 100.0, 10)]),
        ]))

        XCTAssertNil(summary.distanceMeters)
        XCTAssertNil(summary.durationSeconds)
        XCTAssertFalse(summary.isCardio)
    }

    /// A Hevy session logged without any metric at all is not cardio either:
    /// nothing to show as distance or time, so it keeps reading as volume.
    func testASessionWithoutAnyMetricIsNotCardio() {
        let summary = WorkoutSummary(workout: workout(exercises: [
            ("Plank", [(SetType.normal, nil, nil)]),
        ]))

        XCTAssertFalse(summary.isCardio)
    }

    // MARK: - kind decides what is cardio (#180)

    /// A `WeightTraining` session from Strava logs a duration and no load, so
    /// the old heuristic called it cardio. The mapped sport says otherwise,
    /// and it wins.
    func testAStrengthSessionFromAnEnduranceSourceIsNotCardio() {
        let summary = WorkoutSummary(workout: Workout(
            id: "strava:2",
            title: "Gym",
            startTime: Date(timeIntervalSince1970: 1_750_000_000),
            source: .strava,
            kind: .strength,
            exercises: [
                Exercise(index: 0, title: "WeightTraining", sets: [
                    ExerciseSet(index: 0, type: .normal, durationSeconds: 3_600),
                ]),
            ]
        ))

        XCTAssertEqual(summary.kind, .strength)
        XCTAssertFalse(summary.isCardio)
    }

    /// A row cached before V5 has no sport recorded and reads as `.other`
    /// (see `Workout.kind`), so the heuristic still has to answer for it —
    /// otherwise a migrated run would stop showing its distance.
    func testASessionCachedWithoutAKindFallsBackToTheHeuristic() {
        let workout = stravaRun(distance: 5_000, movingTime: 1_800)
        workout.kindRawValue = nil

        let summary = WorkoutSummary(workout: workout)

        XCTAssertEqual(summary.kind, .other)
        XCTAssertTrue(summary.isCardio)
    }

    /// Hevy has no sport vocabulary, so every Hevy session is `.strength` by
    /// default rather than by classification. A treadmill session logged
    /// there has to keep reading as cardio.
    func testAHevySessionWithOnlyADurationIsStillCardio() {
        let summary = WorkoutSummary(workout: Workout(
            id: "w-1",
            title: "Conditioning",
            startTime: Date(timeIntervalSince1970: 1_750_000_000),
            exercises: [
                Exercise(index: 0, title: "Treadmill", sets: [
                    ExerciseSet(index: 0, type: .normal, durationSeconds: 1_200),
                ]),
            ]
        ))

        XCTAssertEqual(summary.kind, .strength)
        XCTAssertEqual(summary.source, .hevy)
        XCTAssertTrue(summary.isCardio)
    }

    private func stravaRun(distance: Double, movingTime: Int, source: ConnectorSource = .strava) -> Workout {
        Workout(
            id: "\(source.rawValue):1",
            title: "Morning Run",
            startTime: Date(timeIntervalSince1970: 1_750_000_000),
            source: source,
            kind: .run,
            exercises: [
                Exercise(index: 0, title: "Run", sets: [
                    ExerciseSet(index: 0, type: .normal, distanceMeters: distance, durationSeconds: movingTime),
                ]),
            ]
        )
    }

    func testSplitSumsToTheWorkoutVolume() {
        let summary = WorkoutSummary(workout: workout(exercises: [
            ("Bench Press (Barbell)", [(SetType.normal, 100.0, 10)]),
            ("Bent Over Row (Barbell)", [(SetType.normal, 80.0, 8)]),
            ("Plank", [(SetType.normal, nil, nil)]),
        ]))

        let distributed = summary.muscleLoads.reduce(0) { $0 + $1.volumeKg }
        XCTAssertEqual(distributed, summary.volumeKg, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func workout(
        exercises: [(title: String, sets: [(type: SetType, weight: Double?, reps: Int?)])]
    ) -> Workout {
        Workout(
            id: "workout",
            title: "Session",
            startTime: Date(timeIntervalSince1970: 1_750_000_000),
            exercises: exercises.enumerated().map { index, exercise in
                Exercise(
                    index: index,
                    title: exercise.title,
                    sets: exercise.sets.enumerated().map { setIndex, set in
                        ExerciseSet(index: setIndex, type: set.type, weightKg: set.weight, reps: set.reps)
                    }
                )
            }
        )
    }
}

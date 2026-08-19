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

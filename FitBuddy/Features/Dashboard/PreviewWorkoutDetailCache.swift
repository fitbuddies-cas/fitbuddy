import Foundation

#if DEBUG
/// In-memory `WorkoutDetailReading` for SwiftUI previews, alongside
/// `PreviewWorkoutCache` (#98).
///
/// Debug-only: the shipped app always reads the real `WorkoutStore`. Previews
/// cannot spin up a SwiftData container per canvas, so they get plain values.
struct PreviewWorkoutDetailCache: WorkoutDetailReading {
    /// Concrete and `Sendable`, unlike a bare `Error` existential — see
    /// `PreviewWorkoutCache.Failure`.
    enum Failure: Error, Sendable {
        case cacheUnavailable
    }

    let details: [WorkoutDetail]
    /// Set to render the detail screen's failure state.
    var failure: Failure?

    func workoutDetail(id: String) async throws -> WorkoutDetail? {
        if let failure { throw failure }
        return details.first { $0.id == id }
    }
}

extension PreviewWorkoutDetailCache {
    static let filled = PreviewWorkoutDetailCache(details: [session])

    static let failing = PreviewWorkoutDetailCache(details: [session], failure: .cacheUnavailable)

    /// One push session covering every rendering case the screen has: a
    /// barbell lift with a warm-up and an RPE, a machine exercise in a
    /// superset, a bodyweight exercise with no weight at all, and a cardio
    /// finisher logged as distance and time.
    static let session: WorkoutDetail = {
        let exercises = [
            exercise(
                index: 0,
                title: "Bench Press (Barbell)",
                notes: "Paused first rep of every set.",
                sets: [
                    SetDetail(index: 0, type: .warmup, weightKg: 60, reps: 10,
                              distanceMeters: nil, durationSeconds: nil, rpe: nil),
                    SetDetail(index: 1, type: .normal, weightKg: 102.5, reps: 8,
                              distanceMeters: nil, durationSeconds: nil, rpe: 8),
                    SetDetail(index: 2, type: .normal, weightKg: 102.5, reps: 8,
                              distanceMeters: nil, durationSeconds: nil, rpe: 9),
                    SetDetail(index: 3, type: .normal, weightKg: 102.5, reps: 7,
                              distanceMeters: nil, durationSeconds: nil, rpe: 9.5),
                ]
            ),
            exercise(
                index: 1,
                title: "Shoulder Press (Dumbbell)",
                supersetID: 1,
                sets: (0..<3).map { index in
                    SetDetail(index: index, type: .normal, weightKg: 26, reps: 10,
                              distanceMeters: nil, durationSeconds: nil, rpe: 8)
                }
            ),
            exercise(
                index: 2,
                title: "Dips",
                supersetID: 1,
                sets: (0..<3).map { index in
                    SetDetail(index: index, type: .normal, weightKg: nil, reps: 12 - index,
                              distanceMeters: nil, durationSeconds: nil, rpe: nil)
                }
            ),
            exercise(
                index: 3,
                title: "Treadmill",
                sets: [
                    SetDetail(index: 0, type: .normal, weightKg: nil, reps: nil,
                              distanceMeters: 2_400, durationSeconds: 780, rpe: nil),
                ]
            ),
        ]
        // Totalled from the exercises, exactly as `WorkoutDetail.init(workout:)`
        // does — a preview must not show figures the app could never produce.
        return WorkoutDetail(
            id: "preview-detail",
            title: "Push Day",
            workoutDescription: "Felt strong, bar speed held up across all top sets.",
            startTime: .now.addingTimeInterval(-4 * 3_600),
            endTime: .now.addingTimeInterval(-4 * 3_600 + 4_320),
            volumeKg: exercises.reduce(0) { $0 + $1.volumeKg },
            countedSetCount: exercises.reduce(0) { $0 + $1.countedSetCount },
            exercises: exercises
        )
    }()

    /// Builds one exercise and derives the two totals the same way the real
    /// projection does, so the preview cannot show figures the app never would.
    private static func exercise(
        index: Int,
        title: String,
        notes: String? = nil,
        supersetID: Int? = nil,
        sets: [SetDetail]
    ) -> ExerciseDetail {
        let counted = sets.filter(\.countsTowardsVolume)
        return ExerciseDetail(
            index: index,
            title: title,
            notes: notes,
            supersetID: supersetID,
            muscleGroup: MuscleGroup.from(exerciseTitle: title),
            sets: sets,
            volumeKg: counted.reduce(0) { total, set in
                guard let weight = set.weightKg, let reps = set.reps else { return total }
                return total + weight * Double(reps)
            },
            countedSetCount: counted.count
        )
    }
}
#endif

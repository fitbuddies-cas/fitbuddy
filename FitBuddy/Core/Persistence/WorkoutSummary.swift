import Foundation
import SwiftData

/// A cached workout reduced to the `Sendable` values the dashboard shows.
///
/// `WorkoutStore` hands these out instead of `@Model` instances: a `Workout`
/// is bound to its `ModelContext` and cannot cross an actor boundary, so the
/// aggregation happens where the models live and only value types travel.
struct WorkoutSummary: Equatable, Identifiable, Sendable {
    /// Hevy's workout id.
    let id: String
    let title: String
    let startTime: Date
    /// Training volume in kg: Σ (weight × reps) over all counted sets.
    let volumeKg: Double
    let exerciseCount: Int
    /// Sets that counted towards `volumeKg` (warm-ups excluded).
    let countedSetCount: Int
    /// The workout's volume split by muscle group, one entry per group it
    /// loaded. Feeds the dashboard's distribution chart (#27).
    let muscleLoads: [MuscleLoad]

    /// - Parameter muscleLoads: Defaults to none, so a caller that only cares
    ///   about the totals — a test fixture, a list row — stays unaffected.
    init(
        id: String,
        title: String,
        startTime: Date,
        volumeKg: Double,
        exerciseCount: Int,
        countedSetCount: Int,
        muscleLoads: [MuscleLoad] = []
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.volumeKg = volumeKg
        self.exerciseCount = exerciseCount
        self.countedSetCount = countedSetCount
        self.muscleLoads = muscleLoads
    }
}

extension WorkoutSummary {
    /// Reduces a cached workout. Must be called on the actor owning `workout`.
    init(workout: Workout) {
        let countedSets = workout.exercises
            .flatMap(\.sets)
            .filter { $0.type.countsTowardsVolume }

        // Per exercise, so the muscle group is decided once per movement and
        // the split adds up to the workout's own volume.
        let loads = workout.exercises.map { exercise -> MuscleLoad in
            let sets = exercise.sets.filter { $0.type.countsTowardsVolume }
            return MuscleLoad(
                group: MuscleGroup.from(exerciseTitle: exercise.title),
                volumeKg: Self.volume(of: sets),
                setCount: sets.count
            )
        }

        self.init(
            id: workout.id,
            title: workout.title,
            startTime: workout.startTime,
            volumeKg: Self.volume(of: countedSets),
            exerciseCount: workout.exercises.count,
            countedSetCount: countedSets.count,
            muscleLoads: MuscleLoad.merged(loads)
        )
    }

    /// Σ (weight × reps) over `sets`.
    ///
    /// A set contributes only with both numbers present: a bodyweight or
    /// cardio set has no kg volume, and treating its missing weight as 0 would
    /// be the same result with a worse intent.
    private static func volume(of sets: [ExerciseSet]) -> Double {
        sets.reduce(0) { total, set in
            guard let weight = set.weightKg, let reps = set.reps else { return total }
            return total + weight * Double(reps)
        }
    }
}

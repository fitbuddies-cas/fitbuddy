import Foundation
import SwiftData

/// A cached workout reduced to the `Sendable` values the dashboard shows.
///
/// `WorkoutStore` hands these out instead of `@Model` instances: a `Workout`
/// is bound to its `ModelContext` and cannot cross an actor boundary, so the
/// aggregation happens where the models live and only value types travel.
/// `Hashable` so the dashboard can push a row as a `NavigationLink` value
/// (#98): the detail screen is addressed by the summary the user tapped, and
/// `.navigationDestination(for:)` builds its ViewModel once per push instead
/// of once per rendered row.
struct WorkoutSummary: Hashable, Identifiable, Sendable {
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
                volumeKg: sets.trainingVolumeKg,
                setCount: sets.count
            )
        }

        self.init(
            id: workout.id,
            title: workout.title,
            startTime: workout.startTime,
            volumeKg: countedSets.trainingVolumeKg,
            exerciseCount: workout.exercises.count,
            countedSetCount: countedSets.count,
            muscleLoads: MuscleLoad.merged(loads)
        )
    }
}

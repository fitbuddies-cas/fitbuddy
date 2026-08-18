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
}

extension WorkoutSummary {
    /// Reduces a cached workout. Must be called on the actor owning `workout`.
    init(workout: Workout) {
        let countedSets = workout.exercises
            .flatMap(\.sets)
            .filter { $0.type.countsTowardsVolume }

        self.init(
            id: workout.id,
            title: workout.title,
            startTime: workout.startTime,
            // A set contributes only with both numbers present: a bodyweight
            // or cardio set has no kg volume, and treating its missing weight
            // as 0 would be the same result with a worse intent.
            volumeKg: countedSets.reduce(0) { total, set in
                guard let weight = set.weightKg, let reps = set.reps else { return total }
                return total + weight * Double(reps)
            },
            exerciseCount: workout.exercises.count,
            countedSetCount: countedSets.count
        )
    }
}

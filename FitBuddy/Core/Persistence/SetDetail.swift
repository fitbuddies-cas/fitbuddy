import Foundation

/// A single logged set, reduced to the `Sendable` values the workout detail
/// screen shows (#98).
///
/// Every metric stays optional, exactly as `ExerciseSet` stores it: Hevy logs
/// only what the exercise type requires, and a bodyweight set has no weight to
/// report. Substituting a zero here would turn "not logged" into "0 kg" — a
/// wrong number instead of a missing one.
struct SetDetail: Equatable, Identifiable, Sendable {
    /// Position of the set within its exercise, as ordered in Hevy.
    let index: Int
    let type: SetType
    let weightKg: Double?
    let reps: Int?
    let distanceMeters: Double?
    let durationSeconds: Int?
    /// Rate of perceived exertion (6–10) when the user logged it.
    let rpe: Double?

    var id: Int { index }

    /// Whether this set counted towards the exercise's volume. Warm-ups do
    /// not, and the screen has to say so rather than silently dropping them.
    var countsTowardsVolume: Bool { type.countsTowardsVolume }
}

extension SetDetail {
    /// Reduces a cached set. Must be called on the actor owning `set`.
    init(set: ExerciseSet) {
        self.init(
            index: set.index,
            type: set.type,
            weightKg: set.weightKg,
            reps: set.reps,
            distanceMeters: set.distanceMeters,
            durationSeconds: set.durationSeconds,
            rpe: set.rpe
        )
    }
}

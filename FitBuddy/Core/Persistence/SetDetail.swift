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
    /// The reps the routine prescribed for this set (#240), `nil` when there
    /// was no routine or no target — what the 2-for-2 rule (ADR-013) reads.
    /// Defaulted, so the many call sites that describe a set without a plan
    /// stay as they are.
    var targetReps: Int? = nil

    var id: Int { index }

    /// Whether this set counted towards the exercise's volume. Warm-ups do
    /// not, and the screen has to say so rather than silently dropping them.
    var countsTowardsVolume: Bool { type.countsTowardsVolume }
}

extension Sequence where Element == SetDetail {
    /// The sets paired with their number among the *counted* ones, 1-based —
    /// `nil` for every set outside the volume.
    ///
    /// Outside the volume is more than the warm-ups: `SetType.countsTowardsVolume`
    /// also excludes `.unknown`, where a missing type and every type a later
    /// Hevy adds end up.
    ///
    /// Here rather than on one screen's model because two screens now show the
    /// same sets — the card inside a session and the history on the statistics
    /// screen (#163). Numbering them from separate implementations is how a
    /// leading unknown set once ended up as number 0.
    var numbered: [(set: SetDetail, number: Int?)] {
        var number = 0
        return map { set in
            guard set.countsTowardsVolume else { return (set, nil) }
            number += 1
            return (set, number)
        }
    }
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
            rpe: set.rpe,
            targetReps: set.targetReps
        )
    }
}

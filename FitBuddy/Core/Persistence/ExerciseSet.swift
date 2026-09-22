import Foundation
import SwiftData

/// The current `ExerciseSet` model — see `FitBuddySchemaV5`.
typealias ExerciseSet = FitBuddySchemaV5.ExerciseSet

extension FitBuddySchemaV5 {
    /// A single logged set, the leaf of the cached `Workout → Exercise →
    /// ExerciseSet` hierarchy.
    ///
    /// Every metric is optional because a source logs only what the exercise
    /// type requires: a barbell set has weight and reps, a treadmill set or a
    /// Strava run has distance and duration, a bodyweight set has neither
    /// weight nor distance.
    @Model
    final class ExerciseSet {
        /// Position of the set within its exercise, as ordered at the source.
        var index: Int
        /// Raw source set type — read it through `type`.
        var typeRawValue: String
        var weightKg: Double?
        var reps: Int?
        var distanceMeters: Double?
        var durationSeconds: Int?
        /// Rate of perceived exertion (6–10) when the user logged it.
        var rpe: Double?

        /// Inverse of `Exercise.sets`; owned by the parent's cascade delete rule.
        var exercise: Exercise?

        /// Typed view of `typeRawValue`.
        var type: SetType {
            SetType.from(typeRawValue)
        }

        init(
            index: Int,
            type: SetType,
            weightKg: Double? = nil,
            reps: Int? = nil,
            distanceMeters: Double? = nil,
            durationSeconds: Int? = nil,
            rpe: Double? = nil
        ) {
            self.index = index
            self.typeRawValue = type.rawValue
            self.weightKg = weightKg
            self.reps = reps
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.rpe = rpe
        }
    }
}

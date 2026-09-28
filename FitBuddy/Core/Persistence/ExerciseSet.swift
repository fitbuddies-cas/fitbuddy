import Foundation
import SwiftData

/// The current `ExerciseSet` model — see `FitBuddySchemaV8`.
typealias ExerciseSet = FitBuddySchemaV8.ExerciseSet

extension FitBuddySchemaV8 {
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
        /// The repetitions this set was meant to reach, from the routine the
        /// workout was logged against (#240, ADR-013) — `nil` when there was
        /// no routine, the routine set had no target, or the row predates V6.
        /// "No target" is a state the 2-for-2 rule reads as not checkable,
        /// not as met.
        var targetReps: Int?

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
            rpe: Double? = nil,
            targetReps: Int? = nil
        ) {
            self.index = index
            self.typeRawValue = type.rawValue
            self.weightKg = weightKg
            self.reps = reps
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.rpe = rpe
            self.targetReps = targetReps
        }
    }
}

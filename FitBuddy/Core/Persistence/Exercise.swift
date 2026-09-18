import Foundation
import SwiftData

/// The current `Exercise` model — see `FitBuddySchemaV5`.
typealias Exercise = FitBuddySchemaV5.Exercise

extension FitBuddySchemaV5 {
    /// One exercise performed within a cached `Workout`, holding its logged sets.
    @Model
    final class Exercise {
        /// Position of the exercise within its workout, as ordered at the source.
        var index: Int
        var title: String
        var notes: String?
        /// Hevy's `exercise_template_id` — the stable identity of the movement
        /// across workouts, used by per-exercise progression views (US-9).
        var templateID: String?
        /// Hevy's superset grouping id; `nil` when the exercise stands alone.
        var supersetID: Int?

        /// Deleting an exercise deletes its sets — no orphaned rows survive a
        /// cache replacement.
        @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exercise)
        var sets: [ExerciseSet]

        /// Inverse of `Workout.exercises`; owned by the parent's cascade delete rule.
        var workout: Workout?

        init(
            index: Int,
            title: String,
            notes: String? = nil,
            templateID: String? = nil,
            supersetID: Int? = nil,
            sets: [ExerciseSet] = []
        ) {
            self.index = index
            self.title = title
            self.notes = notes
            self.templateID = templateID
            self.supersetID = supersetID
            self.sets = sets
        }
    }
}

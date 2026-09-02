import Foundation
import SwiftData

/// A cached Hevy workout session — the root of the `Workout → Exercise →
/// ExerciseSet` hierarchy that backs the offline dashboard (US-2 AC2).
///
/// - Note: `id` holds Hevy's workout id and is unique in practice, but is not
///   marked `@Attribute(.unique)`. `WorkoutStore` replaces the whole cached
///   window per sync instead of upserting, so the constraint would buy
///   nothing.
@Model
final class Workout {
    /// Hevy's workout id (UUID string).
    var id: String
    var title: String
    /// Hevy's free-text `description`; renamed to avoid shadowing
    /// `CustomStringConvertible.description`.
    var workoutDescription: String?
    var startTime: Date
    var endTime: Date?
    /// Hevy's `updated_at`, kept for the delta-sync via `/workouts/events`
    /// planned in #43.
    var updatedAt: Date?

    /// Deleting a workout deletes its exercises (and, transitively, their sets).
    @Relationship(deleteRule: .cascade, inverse: \Exercise.workout)
    var exercises: [Exercise]

    init(
        id: String,
        title: String,
        workoutDescription: String? = nil,
        startTime: Date,
        endTime: Date? = nil,
        updatedAt: Date? = nil,
        exercises: [Exercise] = []
    ) {
        self.id = id
        self.title = title
        self.workoutDescription = workoutDescription
        self.startTime = startTime
        self.endTime = endTime
        self.updatedAt = updatedAt
        self.exercises = exercises
    }
}

import Foundation
import SwiftData

/// The current `Workout` model — see `FitBuddySchemaV2`.
typealias Workout = FitBuddySchemaV2.Workout

extension FitBuddySchemaV2 {
    /// A cached training session — the root of the `Workout → Exercise →
    /// ExerciseSet` hierarchy that backs the offline dashboard (US-2 AC2).
    ///
    /// - Note: `id` holds the source's own id and is unique in practice, but
    ///   is not marked `@Attribute(.unique)`. `WorkoutStore` replaces a
    ///   source's whole cached window per sync instead of upserting, so the
    ///   constraint would buy nothing.
    @Model
    final class Workout {
        /// The source's workout id — Hevy's UUID string, or `strava:<id>`.
        var id: String
        var title: String
        /// The source's free-text description; renamed to avoid shadowing
        /// `CustomStringConvertible.description`.
        var workoutDescription: String?
        var startTime: Date
        var endTime: Date?
        /// The source's `updated_at`, kept for the delta-sync via
        /// `/workouts/events` planned in #43.
        var updatedAt: Date?
        /// `ConnectorSource.rawValue` of the provider that delivered this
        /// session (#141) — read it through `source`.
        ///
        /// The default is what the V1 → V2 migration fills existing rows
        /// with, and every row the previous build wrote came from Hevy. A
        /// literal rather than `ConnectorSource.hevy.rawValue` so the schema's
        /// default does not depend on evaluating another type.
        var sourceRawValue: String = "hevy"

        /// Deleting a workout deletes its exercises (and, transitively, their sets).
        @Relationship(deleteRule: .cascade, inverse: \Exercise.workout)
        var exercises: [Exercise]

        /// Typed view of `sourceRawValue`. An unknown raw value — a store
        /// written by a newer build — reads as Hevy rather than crashing.
        var source: ConnectorSource {
            ConnectorSource(rawValue: sourceRawValue) ?? .hevy
        }

        init(
            id: String,
            title: String,
            workoutDescription: String? = nil,
            startTime: Date,
            endTime: Date? = nil,
            updatedAt: Date? = nil,
            source: ConnectorSource = .hevy,
            exercises: [Exercise] = []
        ) {
            self.id = id
            self.title = title
            self.workoutDescription = workoutDescription
            self.startTime = startTime
            self.endTime = endTime
            self.updatedAt = updatedAt
            self.sourceRawValue = source.rawValue
            self.exercises = exercises
        }
    }
}

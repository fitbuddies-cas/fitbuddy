import Foundation
import SwiftData

/// The current `Workout` model — see `FitBuddySchemaV8`.
typealias Workout = FitBuddySchemaV8.Workout

extension FitBuddySchemaV8 {
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
        /// `ActivityKind.rawValue` of the sport this session was (#180) —
        /// read it through `kind`.
        ///
        /// Optional rather than defaulted, because "not recorded" is what the
        /// V4 → V5 stage truthfully fills existing rows with: a store written
        /// before this version holds Strava and Polar sessions too, and
        /// defaulting those to `strength` would file a cached run under the
        /// wrong domain. `kind` resolves the gap from the source instead; the
        /// next sync replaces the window and fills the column for real.
        var kindRawValue: String?
        /// The source's id of the routine this session was logged against
        /// (Hevy's `routine_id`, #240) — `nil` for a freely logged workout,
        /// for an endurance source's session, and for every row written
        /// before V6.
        var routineID: String?
        /// The routine's `updated_at` as it was when this session was
        /// **first** cached. Snapshotted with the targets on the sets, not
        /// joined live: a routine the user edits after training has no
        /// version history, so the only record of what the session was
        /// compared against is the one taken then. A later sync rewrites the
        /// window but carries this snapshot over —
        /// `WorkoutStore.replaceCachedWorkouts` — so it never moves.
        var routineUpdatedAt: Date?

        /// Session-level endurance metrics, flat — SwiftData stores scalars,
        /// not a nested `CardioMetrics` (#180). Read them through `cardio`,
        /// which is also the only thing that writes them.
        var cardioAverageHeartRate: Int?
        var cardioMaxHeartRate: Int?
        var cardioElevationGainMeters: Double?
        var cardioAverageSpeedMetersPerSecond: Double?
        var cardioEnergyKilojoules: Double?
        /// Strava's Relative Effort — see `CardioMetrics.relativeEffort`.
        /// Named `cardioPerceivedEffort` up to V7; `originalName` lets the
        /// V7 → V8 stage carry the stored values over (#243).
        @Attribute(originalName: "cardioPerceivedEffort")
        var cardioRelativeEffort: Double?
        var cardioActiveCalories: Int?
        var cardioDistanceMeters: Double?
        var cardioDurationSeconds: Int?
        var cardioTrainingLoad: Double?

        /// Deleting a workout deletes its exercises (and, transitively, their sets).
        @Relationship(deleteRule: .cascade, inverse: \Exercise.workout)
        var exercises: [Exercise]

        /// Typed view of `sourceRawValue`. An unknown raw value — a store
        /// written by a newer build — reads as Hevy rather than crashing.
        var source: ConnectorSource {
            ConnectorSource(rawValue: sourceRawValue) ?? .hevy
        }

        /// Typed view of `kindRawValue`. A row with none — written before V5
        /// — falls back to what its source can still tell us: a Hevy workout
        /// is strength training, an endurance source's session is `.other`,
        /// because which discipline it was is exactly what was not recorded.
        /// An unknown raw value, from a store written by a newer build, reads
        /// the same way.
        var kind: ActivityKind {
            if let kindRawValue, let kind = ActivityKind(rawValue: kindRawValue) { return kind }
            return source.isEnduranceSource ? .other : .strength
        }

        /// Typed view of the flat cardio columns; `nil` when the session
        /// recorded none, so "is there cardio data?" stays one check.
        var cardio: CardioMetrics? {
            CardioMetrics(
                averageHeartRate: cardioAverageHeartRate,
                maxHeartRate: cardioMaxHeartRate,
                elevationGainMeters: cardioElevationGainMeters,
                averageSpeedMetersPerSecond: cardioAverageSpeedMetersPerSecond,
                energyKilojoules: cardioEnergyKilojoules,
                relativeEffort: cardioRelativeEffort,
                activeCalories: cardioActiveCalories,
                distanceMeters: cardioDistanceMeters,
                durationSeconds: cardioDurationSeconds,
                trainingLoad: cardioTrainingLoad
            ).nonEmpty
        }

        init(
            id: String,
            title: String,
            workoutDescription: String? = nil,
            startTime: Date,
            endTime: Date? = nil,
            updatedAt: Date? = nil,
            source: ConnectorSource = .hevy,
            kind: ActivityKind = .strength,
            exercises: [Exercise] = [],
            cardio: CardioMetrics? = nil,
            routineID: String? = nil,
            routineUpdatedAt: Date? = nil
        ) {
            self.id = id
            self.title = title
            self.workoutDescription = workoutDescription
            self.startTime = startTime
            self.endTime = endTime
            self.updatedAt = updatedAt
            self.sourceRawValue = source.rawValue
            self.kindRawValue = kind.rawValue
            self.exercises = exercises
            self.routineID = routineID
            self.routineUpdatedAt = routineUpdatedAt
            self.cardioAverageHeartRate = cardio?.averageHeartRate
            self.cardioMaxHeartRate = cardio?.maxHeartRate
            self.cardioElevationGainMeters = cardio?.elevationGainMeters
            self.cardioAverageSpeedMetersPerSecond = cardio?.averageSpeedMetersPerSecond
            self.cardioEnergyKilojoules = cardio?.energyKilojoules
            self.cardioRelativeEffort = cardio?.relativeEffort
            self.cardioActiveCalories = cardio?.activeCalories
            self.cardioDistanceMeters = cardio?.distanceMeters
            self.cardioDurationSeconds = cardio?.durationSeconds
            self.cardioTrainingLoad = cardio?.trainingLoad
        }
    }
}

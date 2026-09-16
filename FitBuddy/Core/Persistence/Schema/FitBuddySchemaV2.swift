import Foundation
import SwiftData

/// The store schema as shipped between `Activity.source` (#141) and the
/// persisted analysis report (#176): V1 plus `Workout.sourceRawValue`.
///
/// A frozen snapshot, like `FitBuddySchemaV1`: it exists so
/// `FitBuddyMigrationPlan` can recognise a store written by the previous
/// build and migrate it forward. **Never edit the models in here.** A change
/// to what the app stores is a new schema version, not a change to an old
/// one — editing this file would make every installed store come back as
/// "unknown model version" and fall back to an empty in-memory container.
///
/// Four `@Model` classes in one file, against the one-type-per-file rule on
/// purpose: `VersionedSchema` requires them nested, and a historic schema is
/// read as a whole or not at all. Only the stored attributes matter here —
/// the typed accessors and convenience initialisers of the live models are
/// left out, because nothing in the app instantiates these.
enum FitBuddySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }

    @Model
    final class Workout {
        var id: String
        var title: String
        var workoutDescription: String?
        var startTime: Date
        var endTime: Date?
        var updatedAt: Date?
        var sourceRawValue: String = "hevy"

        @Relationship(deleteRule: .cascade, inverse: \Exercise.workout)
        var exercises: [Exercise]

        init(
            id: String,
            title: String,
            workoutDescription: String? = nil,
            startTime: Date,
            endTime: Date? = nil,
            updatedAt: Date? = nil,
            sourceRawValue: String = "hevy",
            exercises: [Exercise] = []
        ) {
            self.id = id
            self.title = title
            self.workoutDescription = workoutDescription
            self.startTime = startTime
            self.endTime = endTime
            self.updatedAt = updatedAt
            self.sourceRawValue = sourceRawValue
            self.exercises = exercises
        }
    }

    @Model
    final class Exercise {
        var index: Int
        var title: String
        var notes: String?
        var templateID: String?
        var supersetID: Int?

        @Relationship(deleteRule: .cascade, inverse: \ExerciseSet.exercise)
        var sets: [ExerciseSet]

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

    @Model
    final class ExerciseSet {
        var index: Int
        var typeRawValue: String
        var weightKg: Double?
        var reps: Int?
        var distanceMeters: Double?
        var durationSeconds: Int?
        var rpe: Double?

        var exercise: Exercise?

        init(
            index: Int,
            typeRawValue: String,
            weightKg: Double? = nil,
            reps: Int? = nil,
            distanceMeters: Double? = nil,
            durationSeconds: Int? = nil,
            rpe: Double? = nil
        ) {
            self.index = index
            self.typeRawValue = typeRawValue
            self.weightKg = weightKg
            self.reps = reps
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.rpe = rpe
        }
    }

    @Model
    final class AnalysisResult {
        var id: UUID = UUID()
        var text: String
        var generatedAt: Date
        var windowWeeks: Int
        var sessionCount: Int = 0
        var feedback: String?

        init(
            id: UUID = UUID(),
            text: String,
            generatedAt: Date,
            windowWeeks: Int,
            sessionCount: Int,
            feedback: String? = nil
        ) {
            self.id = id
            self.text = text
            self.generatedAt = generatedAt
            self.windowWeeks = windowWeeks
            self.sessionCount = sessionCount
            self.feedback = feedback
        }
    }
}

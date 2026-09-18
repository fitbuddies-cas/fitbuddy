import Foundation
import SwiftData

/// The store schema of the structured analysis report (#176): V3 plus
/// `AnalysisResult.reportJSON`, `.reportVersion` and `.providerRawValue`, so a
/// stored recommendation keeps the cards the user saw and names the provider
/// that wrote it (US-14 AC6). `FitBuddySchemaV5` (#180) follows it.
///
/// A frozen snapshot, like `FitBuddySchemaV2` and `FitBuddySchemaV3`: it
/// exists so `FitBuddyMigrationPlan` can recognise a store written by the
/// previous build and migrate it forward. **Never edit the models in here.** A
/// change to what the app stores is a new schema version, not a change to an
/// old one — editing a version in place makes every installed store of it come
/// back as "unknown model version" and fall back to an empty in-memory
/// container.
///
/// **Why #180 did not grow this version.** V4 was written to absorb the other
/// pending schema changes while it was still open, #180 among them. It stopped
/// being open first: PR #202 is reviewed and about to merge, and the branches
/// above it in the US-14 stack already carry stores written by this exact V4.
/// Reopening it would invalidate those and put a reviewed PR back into review,
/// so the cardio columns became V5 — one lightweight stage instead.
///
/// Four `@Model` classes in one file, against the one-type-per-file rule on
/// purpose: `VersionedSchema` requires them nested, and a historic schema is
/// read as a whole or not at all. Only the stored attributes matter here —
/// the typed accessors and convenience initialisers of the live models are
/// left out, because nothing in the app instantiates these.
enum FitBuddySchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

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
        var goal: String?
        var experience: String?
        var reportJSON: Data?
        var reportVersion: Int = 0
        var providerRawValue: String?
        var feedback: String?

        init(
            id: UUID = UUID(),
            text: String,
            generatedAt: Date,
            windowWeeks: Int,
            sessionCount: Int,
            goal: String? = nil,
            experience: String? = nil,
            reportJSON: Data? = nil,
            reportVersion: Int = 0,
            providerRawValue: String? = nil,
            feedback: String? = nil
        ) {
            self.id = id
            self.text = text
            self.generatedAt = generatedAt
            self.windowWeeks = windowWeeks
            self.sessionCount = sessionCount
            self.goal = goal
            self.experience = experience
            self.reportJSON = reportJSON
            self.reportVersion = reportVersion
            self.providerRawValue = providerRawValue
            self.feedback = feedback
        }
    }
}

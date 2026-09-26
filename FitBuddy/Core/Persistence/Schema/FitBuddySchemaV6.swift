import Foundation
import SwiftData

/// The store schema of the routine targets (#240): V5 plus `Workout.routineID`
/// and `.routineUpdatedAt`, and `ExerciseSet.targetReps` (US-17, ADR-013).
/// `FitBuddySchemaV7` (#268) follows it.
///
/// A frozen snapshot, like `FitBuddySchemaV2` to `FitBuddySchemaV5`: it exists
/// so `FitBuddyMigrationPlan` can recognise a store written by the previous
/// build and migrate it forward. **Never edit the models in here.** A change
/// to what the app stores is a new schema version, not a change to an old one
/// — editing a version in place makes every installed store of it come back
/// as "unknown model version" and fall back to an empty in-memory container.
///
/// **Why #268 did not grow this version.** V6 reached `develop` with the
/// US-17 wave, so team devices hold stores written by exactly this V6. The
/// send-confirmation column therefore became V7 — one lightweight stage
/// instead.
///
/// Four `@Model` classes in one file, against the one-type-per-file rule on
/// purpose: `VersionedSchema` requires them nested, and a historic schema is
/// read as a whole or not at all. Only the stored attributes matter here —
/// the typed accessors and convenience initialisers of the live models are
/// left out, because nothing in the app instantiates these.
enum FitBuddySchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

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
        var kindRawValue: String?
        var routineID: String?
        var routineUpdatedAt: Date?

        var cardioAverageHeartRate: Int?
        var cardioMaxHeartRate: Int?
        var cardioElevationGainMeters: Double?
        var cardioAverageSpeedMetersPerSecond: Double?
        var cardioEnergyKilojoules: Double?
        var cardioPerceivedEffort: Double?
        var cardioActiveCalories: Int?
        var cardioDistanceMeters: Double?
        var cardioDurationSeconds: Int?
        var cardioTrainingLoad: Double?

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
            kindRawValue: String? = nil,
            routineID: String? = nil,
            routineUpdatedAt: Date? = nil,
            exercises: [Exercise] = [],
            cardioAverageHeartRate: Int? = nil,
            cardioMaxHeartRate: Int? = nil,
            cardioElevationGainMeters: Double? = nil,
            cardioAverageSpeedMetersPerSecond: Double? = nil,
            cardioEnergyKilojoules: Double? = nil,
            cardioPerceivedEffort: Double? = nil,
            cardioActiveCalories: Int? = nil,
            cardioDistanceMeters: Double? = nil,
            cardioDurationSeconds: Int? = nil,
            cardioTrainingLoad: Double? = nil
        ) {
            self.id = id
            self.title = title
            self.workoutDescription = workoutDescription
            self.startTime = startTime
            self.endTime = endTime
            self.updatedAt = updatedAt
            self.sourceRawValue = sourceRawValue
            self.kindRawValue = kindRawValue
            self.routineID = routineID
            self.routineUpdatedAt = routineUpdatedAt
            self.exercises = exercises
            self.cardioAverageHeartRate = cardioAverageHeartRate
            self.cardioMaxHeartRate = cardioMaxHeartRate
            self.cardioElevationGainMeters = cardioElevationGainMeters
            self.cardioAverageSpeedMetersPerSecond = cardioAverageSpeedMetersPerSecond
            self.cardioEnergyKilojoules = cardioEnergyKilojoules
            self.cardioPerceivedEffort = cardioPerceivedEffort
            self.cardioActiveCalories = cardioActiveCalories
            self.cardioDistanceMeters = cardioDistanceMeters
            self.cardioDurationSeconds = cardioDurationSeconds
            self.cardioTrainingLoad = cardioTrainingLoad
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
        var targetReps: Int?

        var exercise: Exercise?

        init(
            index: Int,
            typeRawValue: String,
            weightKg: Double? = nil,
            reps: Int? = nil,
            distanceMeters: Double? = nil,
            durationSeconds: Int? = nil,
            rpe: Double? = nil,
            targetReps: Int? = nil
        ) {
            self.index = index
            self.typeRawValue = typeRawValue
            self.weightKg = weightKg
            self.reps = reps
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.rpe = rpe
            self.targetReps = targetReps
        }
    }

    @Model
    final class AnalysisResult {
        var id: UUID = UUID()
        var text: String
        var generatedAt: Date
        var windowWeeks: Int
        var sessionCount: Int = 0
        var sessionCountsJSON: Data?
        var analysisProfileRawValue: String?
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
            sessionCountsJSON: Data? = nil,
            analysisProfileRawValue: String? = nil,
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
            self.sessionCountsJSON = sessionCountsJSON
            self.analysisProfileRawValue = analysisProfileRawValue
            self.goal = goal
            self.experience = experience
            self.reportJSON = reportJSON
            self.reportVersion = reportVersion
            self.providerRawValue = providerRawValue
            self.feedback = feedback
        }
    }
}

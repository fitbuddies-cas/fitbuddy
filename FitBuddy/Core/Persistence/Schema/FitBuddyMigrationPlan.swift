import Foundation
import SwiftData

/// Orders the store's schema versions and says how to get from each to the
/// next (#141, ADR-001).
///
/// V1 → V2 is lightweight: `Workout.sourceRawValue` is a new attribute with a
/// default, and SwiftData fills existing rows with it — every workout cached by
/// the previous build was a Hevy workout, so `"hevy"` is not a guess. Nothing
/// is transformed or dropped, which is why no custom stage is needed.
///
/// This is also the rehearsal ADR-001 asked for before a second source: the
/// first migration the project runs is the one that can only add a column.
///
/// V2 → V3 is lightweight for the same reason: `AnalysisResult.goal` and
/// `.experience` are new optional attributes (#192), and `nil` on an existing
/// row is the truth — no run before this version had a profile to record.
///
/// V3 → V4 is lightweight as well (#176): `AnalysisResult` gains `reportJSON`
/// and `providerRawValue`, both optional, and `reportVersion` with a default
/// of 0. `nil`, `nil` and 0 are the truth for an existing row — every
/// recommendation stored before this version is prose, and no build before it
/// recorded the provider. The row's `text` is untouched, so it renders as
/// before (US-14 AC6).
///
/// V4 → V5 is lightweight as well (#180, #182, #185): `Workout` gains
/// `kindRawValue` and ten flat cardio columns, and `AnalysisResult` gains
/// `sessionCountsJSON` and `analysisProfileRawValue` — all optional. `nil` is
/// the truth for an existing row: no build before this version read heart
/// rate, elevation, speed or effort off a payload, the sport was never
/// recorded as anything but the session title, no analysis before it counted
/// anything but Hevy sessions, and none of them was run under a profile the
/// user had chosen.
/// `Workout.kind` resolves the missing sport from the row's source rather than
/// guessing `strength` for a cached run, `SessionCountFormat` reads a missing
/// map as that row's own total from Hevy, and the next sync replaces the window
/// and fills the workout columns for real.
///
/// V5 → V6 is lightweight as well (#240): `Workout` gains `routineID` and
/// `routineUpdatedAt`, `ExerciseSet` gains `targetReps`, all optional. `nil`
/// is the truth for an existing row: no build before this version read a
/// routine off the API, so no cached session knows what it was logged
/// against — and the 2-for-2 rule (ADR-013) reads a missing target as not
/// checkable rather than as met. The next sync replaces the window and fills
/// the columns for real.
///
/// V6 → V7 is lightweight as well (#228): `AnalysisResult` gains
/// `validationLogJSON`, optional. `nil` is the truth for an existing row: no
/// build before this version recorded what the validator rejected, and
/// `AnalysisValidationLogFormat` reads a missing log as "not recorded", never
/// as "nothing rejected".
///
/// V7 → V8 is lightweight as well (#243): `Workout.cardioPerceivedEffort` is
/// renamed to `cardioRelativeEffort`, and the attribute carries
/// `originalName`, so SwiftData moves the stored values over instead of
/// dropping the column and adding an empty one. Nothing is transformed — the
/// value was Strava's Relative Effort all along; only the name was wrong.
/// The same stage adds Polar's Training Load Pro columns (#244) —
/// `cardioLoad`, `cardioMuscleLoad`, `cardioPerceivedLoad` and
/// `cardioUserRPERawValue`, all optional. `nil` is the truth for an existing
/// row: no build before this version decoded `training_load_pro`, and the
/// next sync replaces the window and fills the columns for real.
///
/// A store from an older version runs the stages in turn; the migration tests
/// write a V1, a V2, a V3, a V4, a V5, a V6 and a V7 store and open each under
/// the current version.
enum FitBuddyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            FitBuddySchemaV1.self,
            FitBuddySchemaV2.self,
            FitBuddySchemaV3.self,
            FitBuddySchemaV4.self,
            FitBuddySchemaV5.self,
            FitBuddySchemaV6.self,
            FitBuddySchemaV7.self,
            FitBuddySchemaV8.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1toV2,
            migrateV2toV3,
            migrateV3toV4,
            migrateV4toV5,
            migrateV5toV6,
            migrateV6toV7,
            migrateV7toV8,
        ]
    }

    private static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV1.self,
        toVersion: FitBuddySchemaV2.self
    )

    private static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV2.self,
        toVersion: FitBuddySchemaV3.self
    )

    private static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV3.self,
        toVersion: FitBuddySchemaV4.self
    )

    private static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV4.self,
        toVersion: FitBuddySchemaV5.self
    )

    private static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV5.self,
        toVersion: FitBuddySchemaV6.self
    )

    private static let migrateV6toV7 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV6.self,
        toVersion: FitBuddySchemaV7.self
    )

    private static let migrateV7toV8 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV7.self,
        toVersion: FitBuddySchemaV8.self
    )
}

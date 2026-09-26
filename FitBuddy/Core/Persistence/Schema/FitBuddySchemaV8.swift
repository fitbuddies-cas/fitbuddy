import Foundation
import SwiftData

/// The current store schema (#243): V7 with `Workout.cardioPerceivedEffort`
/// renamed to `cardioRelativeEffort`. The column holds Strava's Relative
/// Effort (`suffer_score`), an objective heart-rate-based score — the old
/// name read like a self-assessment and invited exactly the RPE mix-up US-18
/// (#241) rules out. The rename keeps the stored values through
/// `@Attribute(originalName:)`, so the V7 → V8 stage stays lightweight.
///
/// Grown by #244 before reaching `develop`: `Workout` also gains Polar's
/// Training Load Pro values — `cardioLoad`, `cardioMuscleLoad`,
/// `cardioPerceivedLoad` and `cardioUserRPERawValue`, all optional.
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV8.Workout`. The historic `FitBuddySchemaV1` to
/// `FitBuddySchemaV7` keep their models inline, frozen.
///
/// **V8 may only grow until it reaches `develop`.** Another pending change
/// that needs a new version consolidates into this one rather than adding a
/// V9: a store written by one V8 is not recognised by a V8 with other columns
/// — it fails as "unknown model version" and silently falls back to an empty
/// in-memory container. Once a `develop` build has written a V8 store on a
/// team device, that window is closed and the next change is V9.
///
/// For that V9: copy the models of this version inline into a frozen
/// `FitBuddySchemaV8.swift`, move these extensions to V9, and add the stage to
/// `FitBuddyMigrationPlan`. Editing a model of a version that has reached
/// `develop` makes every installed store of that version unrecognisable.
enum FitBuddySchemaV8: VersionedSchema {
    static let versionIdentifier = Schema.Version(8, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

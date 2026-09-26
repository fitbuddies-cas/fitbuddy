import Foundation
import SwiftData

/// The current store schema (#240): V5 plus `Workout.routineID` and
/// `.routineUpdatedAt`, and `ExerciseSet.targetReps`, so a cached Hevy session
/// remembers which routine it was logged against and what each set was meant
/// to reach — the target the 2-for-2 rule of US-17 compares against
/// (ADR-013).
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV6.Workout`. The historic `FitBuddySchemaV1` to
/// `FitBuddySchemaV5` keep their models inline, frozen.
///
/// **V6 may only grow until it reaches `develop`.** Another pending change
/// that needs a new version consolidates into this one rather than adding a
/// V7: a store written by one V6 is not recognised by a V6 with other columns
/// — it fails as "unknown model version" and silently falls back to an empty
/// in-memory container. Once a `develop` build has written a V6 store on a
/// team device, that window is closed and the next change is V7.
///
/// For that V7: copy the models of this version inline into a frozen
/// `FitBuddySchemaV6.swift`, move these extensions to V7, and add the stage to
/// `FitBuddyMigrationPlan`. Editing a model of a version that has reached
/// `develop` makes every installed store of that version unrecognisable.
enum FitBuddySchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

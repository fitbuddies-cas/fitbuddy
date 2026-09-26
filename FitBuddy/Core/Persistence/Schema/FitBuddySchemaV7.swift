import Foundation
import SwiftData

/// The current store schema (#228): V6 plus
/// `AnalysisResult.validationLogJSON`, the record of what the validator
/// rejected, downgraded or overrode in the model's answer (US-16 AC4) —
/// stored with the analysis so the hit rate over several runs is readable
/// (#229).
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV7.Workout`. The historic `FitBuddySchemaV1` to
/// `FitBuddySchemaV6` keep their models inline, frozen.
///
/// **V7 may only grow until it reaches `develop`.** Another pending change
/// that needs a new version consolidates into this one rather than adding a
/// V8: a store written by one V7 is not recognised by a V7 with other columns
/// — it fails as "unknown model version" and silently falls back to an empty
/// in-memory container. Once a `develop` build has written a V7 store on a
/// team device, that window is closed and the next change is V8.
///
/// For that V8: copy the models of this version inline into a frozen
/// `FitBuddySchemaV7.swift`, move these extensions to V8, and add the stage to
/// `FitBuddyMigrationPlan`. Editing a model of a version that has reached
/// `develop` makes every installed store of that version unrecognisable.
enum FitBuddySchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

import Foundation
import SwiftData

/// The current store schema (#176): V3 plus `AnalysisResult.reportJSON`,
/// `.reportVersion` and `.providerRawValue`, so a stored recommendation keeps
/// the cards the user saw and names the provider that wrote it (US-14 AC6).
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV4.Workout`. The historic `FitBuddySchemaV1` to
/// `FitBuddySchemaV3` keep their models inline, frozen.
///
/// **One V4, not two.** #176 first grew V3 in place, next to the training
/// profile (#192, PR #199), which needed a V3 as well. #199 reached `develop`
/// first, and `develop` builds already run on the team's devices: a store
/// written by one V3 is not recognised by a V3 with other columns — it fails
/// as "unknown model version" and silently falls back to an empty in-memory
/// container. So #176 became V4. Other pending changes that need a new
/// version (e.g. #180, `ActivityKind` and cardio fields on `Workout`)
/// consolidate into this V4: V4 may only grow until it reaches `develop`; the
/// next change after that is V5.
///
/// For that V5: copy the models of this version inline into a frozen
/// `FitBuddySchemaV4.swift`, move these extensions to V5, and add the stage to
/// `FitBuddyMigrationPlan`. Editing a model of a version that has reached
/// `develop` makes every installed store of that version unrecognisable.
enum FitBuddySchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

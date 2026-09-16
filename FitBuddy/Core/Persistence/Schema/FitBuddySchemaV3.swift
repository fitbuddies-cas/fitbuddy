import Foundation
import SwiftData

/// The current store schema (#176): V2 plus `AnalysisResult.reportJSON`,
/// `.reportVersion` and `.providerRawValue`, so a stored recommendation keeps
/// the cards the user saw and names the provider that wrote it (US-14 AC6).
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV3.Workout`. The historic `FitBuddySchemaV1` and
/// `FitBuddySchemaV2` keep their models inline, frozen.
///
/// **One V3, not two.** #180 (`ActivityKind` and cardio fields on `Workout`)
/// adds its columns to this same version rather than opening a V4 — as long
/// as V3 has not reached `main`. No build carrying V3 has been distributed
/// before that, so no installed store can hold a V3 that the extended V3
/// would fail to recognise. Once V3 is on `main`, it is frozen like V2 and
/// the next change is a V4.
///
/// When the stored shape changes after that: copy the models of this version
/// inline into a frozen `FitBuddySchemaV3.swift`, move these extensions to a
/// V4, and add the stage to `FitBuddyMigrationPlan`. Editing a model of a
/// shipped version in place makes every installed store unrecognisable.
enum FitBuddySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

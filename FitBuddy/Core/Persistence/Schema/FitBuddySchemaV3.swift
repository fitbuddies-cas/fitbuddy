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
/// **One V3, not two.** Two other changes are known to need a V3 as well:
/// #192 (training profile, PR #199 — `AnalysisResult.goal` and `.experience`)
/// and #180 (`ActivityKind` and cardio fields on `Workout`). V3 may grow in
/// place only until the *first* V3 PR merges into `develop`. `develop` builds
/// already run on the team's devices, and a store written by one V3 is not
/// recognised by a V3 with other columns: it fails as "unknown model version"
/// and silently falls back to an empty in-memory container. So the candidates
/// consolidate into one V3 before the first of them reaches `develop`; any
/// change after that is a V4.
///
/// For that V4: copy the models of this version inline into a frozen
/// `FitBuddySchemaV3.swift`, move these extensions to V4, and add the stage to
/// `FitBuddyMigrationPlan`. Editing a model of a version that has reached
/// `develop` makes every installed store of that version unrecognisable.
enum FitBuddySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

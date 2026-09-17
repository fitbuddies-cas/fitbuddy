import Foundation
import SwiftData

/// The current store schema (#192): V2 plus `AnalysisResult.goal` and
/// `AnalysisResult.experience`, so a stored recommendation remembers the
/// training profile the run was steered by (US-13 AC4).
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV3.Workout`. The historic `FitBuddySchemaV1` and
/// `FitBuddySchemaV2` keep their models inline, frozen.
///
/// When the stored shape changes next: copy the models of this version inline
/// into a frozen `FitBuddySchemaV3.swift`, move these extensions to a V4, and
/// add the stage to `FitBuddyMigrationPlan`. Editing a model of the current
/// version in place makes every installed store unrecognisable.
enum FitBuddySchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

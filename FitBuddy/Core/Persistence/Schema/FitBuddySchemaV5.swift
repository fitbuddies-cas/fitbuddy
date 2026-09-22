import Foundation
import SwiftData

/// The current store schema (#180, #182, #185): V4 plus `Workout.kindRawValue`
/// and the flat cardio columns, so a cached session remembers which sport it
/// was and the heart rate, elevation, speed and effort the source reported,
/// plus `AnalysisResult.sessionCountsJSON` and
/// `AnalysisResult.analysisProfileRawValue`, so a stored recommendation
/// remembers how its sessions split across the sources and which profile
/// produced it (US-15).
///
/// #182 and #185 grew this version in place rather than adding a V6, under the
/// rule below: no V5 store had reached `develop` — #180 created the version in
/// the same wave — so there was no installed store to migrate from.
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV5.Workout`. The historic `FitBuddySchemaV1` to
/// `FitBuddySchemaV4` keep their models inline, frozen.
///
/// **V5 may only grow until it reaches `develop`.** Another pending change
/// that needs a new version consolidates into this one rather than adding a
/// V6: a store written by one V5 is not recognised by a V5 with other columns
/// — it fails as "unknown model version" and silently falls back to an empty
/// in-memory container. Once a `develop` build has written a V5 store on a
/// team device, that window is closed and the next change is V6.
///
/// For that V6: copy the models of this version inline into a frozen
/// `FitBuddySchemaV5.swift`, move these extensions to V6, and add the stage to
/// `FitBuddyMigrationPlan`. Editing a model of a version that has reached
/// `develop` makes every installed store of that version unrecognisable.
enum FitBuddySchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

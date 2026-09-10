import Foundation
import SwiftData

/// The current store schema (#141): V1 plus `Workout.sourceRawValue`, so a
/// cached session knows which `ConnectorSource` delivered it and a sync can
/// replace one source's window without touching the other's.
///
/// The model classes live in their own files as extensions of this enum
/// (`Workout.swift`, `Exercise.swift`, …), each with a top-level typealias so
/// the rest of the app keeps naming them `Workout` and not
/// `FitBuddySchemaV2.Workout`. Only the historic `FitBuddySchemaV1` keeps its
/// models inline.
///
/// Adding a versioned schema on top of an app that shipped without one is the
/// path Apple documents: V1 mirrors the shipped models exactly, so an installed
/// store is recognised as V1 and migrated. Stores older than that — from builds
/// before `AnalysisResult` grew its `id`, say — were migrated by the builds in
/// between and are not modelled here.
enum FitBuddySchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Workout.self, Exercise.self, ExerciseSet.self, AnalysisResult.self]
    }
}

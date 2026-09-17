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
/// A store from V1 runs both stages in turn; the migration test writes a V1
/// store and a V2 store and opens each under the current version.
enum FitBuddyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [FitBuddySchemaV1.self, FitBuddySchemaV2.self, FitBuddySchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    private static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV1.self,
        toVersion: FitBuddySchemaV2.self
    )

    private static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: FitBuddySchemaV2.self,
        toVersion: FitBuddySchemaV3.self
    )
}

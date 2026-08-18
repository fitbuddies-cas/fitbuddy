import Foundation

/// Fetches the dashboard's workout window from a fitness data source and
/// writes it to the local cache.
///
/// Source-agnostic on purpose: the dashboard (#26) depends on this protocol,
/// not on `HevyService`, so it can be tested against a double and survives the
/// move to `FitnessConnector` (ADR-006, #34).
protocol WorkoutSyncing: Sendable {
    /// Loads the last 90 days of workouts, replaces the cache with them and
    /// updates the sync timestamp.
    ///
    /// - Throws: `HevyServiceError`. A thrown `.unauthorized` means the stored
    ///   key was already wiped and the caller must route back to onboarding.
    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult
}

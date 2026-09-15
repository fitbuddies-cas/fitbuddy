import Foundation

/// Fetches the dashboard's workout window from a fitness data source and
/// writes it to the local cache.
///
/// Source-agnostic on purpose: the dashboard (#26) depends on this protocol,
/// not on `WorkoutSyncService`, so it can be tested against a double. The
/// provider behind it is a `FitnessConnector` (ADR-006, #34).
protocol WorkoutSyncing: Sendable {
    /// Loads the last 90 days of workouts, replaces the cache with them and
    /// updates the sync timestamp.
    ///
    /// - Throws: `WorkoutSyncError`. A thrown `.unauthorized` means the stored
    ///   key was already wiped and the caller must route back to onboarding.
    ///   A `CancellationError` means the sync was voided rather than failed:
    ///   the request was cancelled, or the session was reset while the window
    ///   was in flight and nothing was cached (#150) — no banner either way.
    @discardableResult
    func syncRecentWorkouts() async throws -> SyncResult
}

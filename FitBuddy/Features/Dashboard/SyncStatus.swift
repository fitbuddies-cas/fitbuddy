import Foundation

/// State of the dashboard's sync, independent of what the cache holds (#28).
///
/// Kept apart from `WorkoutListState` on purpose: the two answer different
/// questions. `WorkoutListState` says what there is to show, `SyncStatus` says
/// how current it is — a failed sync on top of a full cache still renders the
/// full dashboard, only with a banner above it.
enum SyncStatus: Equatable {
    /// No sync in flight and the last one did not fail — the banner is gone
    /// (AC3).
    case idle
    /// A sync is running.
    case syncing
    /// The last sync failed for every source; cached data stays on screen.
    case failed(SyncFailure)
    /// The last sync went through for some sources but not others (#143):
    /// the timestamp moved and the fresh data is on screen, and these are the
    /// sources that are missing from it. Hevy and Strava can each be here.
    case degraded(failures: [ConnectorSource: SyncFailure])
}

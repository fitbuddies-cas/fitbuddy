import Foundation

/// State of the dashboard's Hevy sync, independent of what the cache holds
/// (#28).
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
    /// The last sync failed; cached data stays on screen.
    case failed(SyncFailure)
}

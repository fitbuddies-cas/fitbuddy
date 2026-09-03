import Foundation

/// Outcome of a successful workout sync.
struct SyncResult: Equatable, Sendable {
    /// Number of workouts inside the window that are now cached.
    let workoutCount: Int
    /// New `lastSyncTimestamp`.
    let syncedAt: Date
    /// Oldest instant the window covers — everything cached starts at or after it.
    let windowStart: Date
}

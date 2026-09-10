import Foundation

/// Outcome of a workout sync that cached at least one source's window.
///
/// With several sources (#143) a sync can succeed for one and fail for
/// another; `failures` carries the ones that did not go through, so the
/// dashboard can keep the fresh data and still say what is missing. A sync in
/// which *every* source failed throws instead — there is nothing to report a
/// success about.
struct SyncResult: Equatable, Sendable {
    /// Number of workouts inside the window that are now cached, over every
    /// source that succeeded.
    let workoutCount: Int
    /// New `lastSyncTimestamp`.
    let syncedAt: Date
    /// Oldest instant the window covers — everything cached starts at or after it.
    let windowStart: Date
    /// Sources that were attempted and failed, with why. Empty when every
    /// connected source synced.
    let failures: [ConnectorSource: WorkoutSyncError]

    /// - Parameter failures: Defaults to none, so a single-source result —
    ///   the DEBUG stub, a test fixture — reads as it always did.
    init(
        workoutCount: Int,
        syncedAt: Date,
        windowStart: Date,
        failures: [ConnectorSource: WorkoutSyncError] = [:]
    ) {
        self.workoutCount = workoutCount
        self.syncedAt = syncedAt
        self.windowStart = windowStart
        self.failures = failures
    }

    /// Whether some connected source did not make it into this sync.
    var isPartial: Bool {
        !failures.isEmpty
    }
}

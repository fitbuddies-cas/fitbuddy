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
    /// Every source this sync attempted, failed ones included, in
    /// `ConnectorSource.allCases` order — what the dashboard's status strip
    /// lists a row for (US-8, #40).
    let sources: [ConnectorSource]

    /// - Parameters:
    ///   - failures: Defaults to none, so a single-source result — the DEBUG
    ///     stub, a test fixture — reads as it always did.
    ///   - sources: Defaults to Hevy alone, for the same reason.
    init(
        workoutCount: Int,
        syncedAt: Date,
        windowStart: Date,
        failures: [ConnectorSource: WorkoutSyncError] = [:],
        sources: [ConnectorSource] = [.hevy]
    ) {
        self.workoutCount = workoutCount
        self.syncedAt = syncedAt
        self.windowStart = windowStart
        self.failures = failures
        self.sources = sources
    }

    /// Whether some connected source did not make it into this sync.
    var isPartial: Bool {
        !failures.isEmpty
    }
}

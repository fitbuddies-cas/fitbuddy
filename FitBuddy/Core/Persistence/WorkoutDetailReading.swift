import Foundation

/// Read access to a single cached workout with its full exercise tree.
///
/// Separate from `WorkoutSummaryReading` for the same reason the two
/// projections are separate: the dashboard reads a window of summaries, the
/// detail screen one whole session. `WorkoutDetailViewModel` depends on this
/// protocol, never on `WorkoutStore`, so it can be tested without a SwiftData
/// container.
protocol WorkoutDetailReading: Sendable {
    /// The cached workout with `id`, or `nil` when it is not in the cache.
    ///
    /// `nil` is a regular answer, not a failure: a sync replaces the whole
    /// window, so the session behind an open screen can disappear between the
    /// tap and the read.
    func workoutDetail(id: String) async throws -> WorkoutDetail?
}

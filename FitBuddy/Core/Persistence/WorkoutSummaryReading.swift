import Foundation

/// Read access to the cached workout window.
///
/// The dashboard depends on this protocol, never on `WorkoutSyncService`: the
/// ViewModel reads the cache only and never triggers an API call itself (#26),
/// and a test double replaces the SwiftData container wholesale.
protocol WorkoutSummaryReading: Sendable {
    /// Cached workouts that started at or after `date`, newest first.
    func workoutSummaries(since date: Date) async throws -> [WorkoutSummary]
}

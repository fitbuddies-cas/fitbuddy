import Foundation
@testable import FitBuddy

/// Test double for the cache read, so `WorkoutListViewModel` can be tested
/// without a SwiftData container.
final class StubWorkoutCache: WorkoutSummaryReading, @unchecked Sendable {
    /// Summaries returned by `workoutSummaries(since:)`.
    var summaries: [WorkoutSummary] = []
    /// When set, the read throws instead of returning `summaries`.
    var error: Error?
    /// The `since` argument of the last call — proves the 90-day boundary.
    private(set) var requestedSince: Date?
    private(set) var callCount = 0

    func workoutSummaries(since date: Date) async throws -> [WorkoutSummary] {
        requestedSince = date
        callCount += 1
        if let error { throw error }
        return summaries
    }

    struct Failure: Error {}
}

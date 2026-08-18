import Foundation
import SwiftData

extension WorkoutStore: WorkoutSummaryReading {
    /// Cached workouts that started at or after `date`, newest first.
    ///
    /// Filtering in the `FetchDescriptor` rather than in Swift keeps workouts
    /// outside the window out of memory; the summaries are built here, inside
    /// the actor, because `Workout` cannot leave it.
    func workoutSummaries(since date: Date) throws -> [WorkoutSummary] {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startTime >= date },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        // Prefetches one level only. `WorkoutSummary` also walks
        // `exercise.sets`, and a key path cannot hop through a to-many
        // relationship (`\.exercises.sets` does not compile), so the sets
        // still fault per exercise. Measure this against a full 90-day cache
        // before the real dashboard ships (#27): if it hurts, the fix is a
        // separate `ExerciseSet` fetch grouped in memory, not this descriptor.
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]
        return try modelContext.fetch(descriptor).map(WorkoutSummary.init(workout:))
    }
}

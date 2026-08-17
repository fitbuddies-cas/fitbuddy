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
        // The dashboard reads the whole hierarchy of every workout it lists,
        // so prefetching avoids one faulting round-trip per relationship.
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]
        return try modelContext.fetch(descriptor).map(WorkoutSummary.init(workout:))
    }
}

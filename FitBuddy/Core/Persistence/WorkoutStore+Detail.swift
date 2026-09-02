import Foundation
import SwiftData

extension WorkoutStore: WorkoutDetailReading {
    /// The cached workout with `id`, or `nil` when it is not in the cache.
    ///
    /// One workout instead of the window's ninety, so the set-faulting caveat
    /// noted in `WorkoutStore+Summaries` does not apply here: prefetching the
    /// exercises leaves at most one fault per exercise of a single session.
    ///
    /// `fetchLimit = 1` because Hevy's id identifies the workout — the store
    /// carries no uniqueness constraint (see `Workout`), so the limit is what
    /// says a second row would be a duplicate rather than a second answer.
    func workoutDetail(id: String) throws -> WorkoutDetail? {
        var descriptor = FetchDescriptor<Workout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]
        return try modelContext.fetch(descriptor).first.map(WorkoutDetail.init(workout:))
    }
}

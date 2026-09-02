import Foundation
import SwiftData

/// Owns every write to the cached workout hierarchy.
///
/// A `@ModelActor` per the Swift-concurrency convention in ARCHITECTURE.md: a
/// `ModelContext` is not `Sendable`, so all writes are serialized here instead
/// of happening on the `@MainActor`. Reads for the UI go through `@Query` /
/// the main context — this actor deliberately returns only `Sendable` values,
/// never `@Model` instances.
@ModelActor
actor WorkoutStore {
    /// Replaces the cached window with `workouts` in a single save.
    ///
    /// The Hevy response for the 90-day window is authoritative, so the cache
    /// is rebuilt rather than merged: this avoids the `@Attribute(.unique)`
    /// upsert path entirely, and it removes workouts the user deleted in Hevy
    /// for free. Delete and insert share one `save()`, so a failure leaves the
    /// previous cache intact.
    func replaceCachedWorkouts(with workouts: [HevyWorkoutDTO]) throws {
        try deleteAllWorkouts()
        for dto in workouts {
            modelContext.insert(dto.makeWorkout())
        }
        try saveOrRollback()
    }

    /// Empties the cache (hard logout, "delete my data").
    func deleteAll() throws {
        try deleteAllWorkouts()
        try saveOrRollback()
    }

    /// Number of cached workouts — the `Sendable` summary callers need.
    func workoutCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Workout>())
    }

    /// Ids of the cached workouts, newest first.
    func cachedWorkoutIDs() throws -> [String] {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        return try modelContext.fetch(descriptor).map(\.id)
    }

    /// Deletes every workout without saving.
    ///
    /// Fetch-then-delete rather than `modelContext.delete(model:)`: the batch
    /// form bypasses the object graph and leaves `Exercise`/`ExerciseSet` rows
    /// orphaned instead of honouring their `.cascade` rule. At ~360 workouts
    /// per window the extra fetch is irrelevant.
    ///
    /// A failing fetch must propagate: swallowing it would let the caller
    /// insert a second copy of the window on top of the old one, and without
    /// `@Attribute(.unique)` on `Workout.id` every workout would then be
    /// cached twice while the sync still reports success.
    private func deleteAllWorkouts() throws {
        for workout in try modelContext.fetch(FetchDescriptor<Workout>()) {
            modelContext.delete(workout)
        }
    }

    /// Saves, discarding the pending changes if the save fails.
    ///
    /// Without the rollback the failed deletes and inserts stay in this
    /// actor's context: reads would report the unsaved state, and the next
    /// successful `save()` would commit the leftovers along with it.
    private func saveOrRollback() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

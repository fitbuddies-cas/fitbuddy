import Foundation
import SwiftData

/// Owns every write to the cached workout hierarchy.
///
/// A `@ModelActor` per the Swift-concurrency convention in ARCHITECTURE.md: a
/// `ModelContext` is not `Sendable`, so all writes are serialized here instead
/// of happening on the `@MainActor`. Reads for the UI go through `@Query` /
/// the main context — this actor deliberately returns only `Sendable` values,
/// never `@Model` instances.
///
/// Writes are scoped to a `ConnectorSource` (#141): each source's window is
/// authoritative for that source only. A Hevy sync that wiped the Strava
/// sessions cached next to it would make the dashboard flicker between one
/// source and the other on every refresh.
@ModelActor
actor WorkoutStore {
    /// Replaces `source`'s cached window with `activities` in a single save,
    /// leaving every other source's sessions untouched.
    ///
    /// Takes the normalized `Activity` (ADR-6, #34), not a provider's DTO: the
    /// cache is the same shape whichever connector filled it. The activities
    /// are expected to come from `source` — the store trusts the caller on
    /// that, since the sync hands one connector's result straight through.
    ///
    /// The source's window is authoritative, so its rows are rebuilt rather
    /// than merged: this avoids the `@Attribute(.unique)` upsert path
    /// entirely, and it removes workouts the user deleted at the source for
    /// free. Delete and insert share one `save()`, so a failure leaves the
    /// previous cache intact.
    ///
    /// One thing survives the rebuild: the **routine snapshot** a session
    /// already carries (#240). The connector hands over the targets as the
    /// routine stands today, and rewriting them on every sync would compare
    /// a past session against a plan that did not apply when it was trained
    /// — the live join ADR-013 rules out. So the first snapshot a session was
    /// cached with is carried over, and a routine the user edits afterwards
    /// reaches only the sessions logged after the edit.
    func replaceCachedWorkouts(from source: ConnectorSource, with activities: [Activity]) throws {
        let snapshots = try routineSnapshots(from: source)
        try deleteWorkouts(from: source)
        for activity in activities {
            let workout = activity.makeWorkout()
            snapshots[activity.id]?.apply(to: workout)
            modelContext.insert(workout)
        }
        try saveOrRollback()
    }

    /// The routine snapshot of every cached session of `source` that has
    /// one, keyed by workout id — read before the rows are deleted.
    private func routineSnapshots(from source: ConnectorSource) throws -> [String: RoutineSnapshot] {
        var snapshots: [String: RoutineSnapshot] = [:]
        for workout in try modelContext.fetch(Self.descriptor(for: source)) where workout.routineUpdatedAt != nil {
            snapshots[workout.id] = RoutineSnapshot(workout: workout)
        }
        return snapshots
    }

    /// What a session was compared against when it was first cached: the
    /// routine, its state, and the target of every set, by exercise and set
    /// index.
    private struct RoutineSnapshot {
        let routineID: String?
        let routineUpdatedAt: Date?
        let targets: [Int: [Int: Int]]

        init(workout: Workout) {
            routineID = workout.routineID
            routineUpdatedAt = workout.routineUpdatedAt
            var targets: [Int: [Int: Int]] = [:]
            for exercise in workout.exercises {
                for set in exercise.sets {
                    if let target = set.targetReps { targets[exercise.index, default: [:]][set.index] = target }
                }
            }
            self.targets = targets
        }

        /// Puts the snapshot onto a freshly mapped workout in place of the
        /// targets the connector just derived. A set the snapshot never saw
        /// — added to the session at the source since — carries no target,
        /// which is the state the 2-for-2 rule reads as not checkable.
        func apply(to workout: Workout) {
            workout.routineID = routineID
            workout.routineUpdatedAt = routineUpdatedAt
            for exercise in workout.exercises {
                for set in exercise.sets {
                    set.targetReps = targets[exercise.index]?[set.index]
                }
            }
        }
    }

    /// Drops one source's sessions — disconnecting Strava, or ending the Hevy
    /// session — and keeps the rest.
    func deleteCachedWorkouts(from source: ConnectorSource) throws {
        try deleteWorkouts(from: source)
        try saveOrRollback()
    }

    /// Empties the cache regardless of source ("delete my data").
    func deleteAll() throws {
        for workout in try modelContext.fetch(FetchDescriptor<Workout>()) {
            modelContext.delete(workout)
        }
        try saveOrRollback()
    }

    /// Number of cached workouts — the `Sendable` summary callers need.
    func workoutCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<Workout>())
    }

    /// Number of cached workouts from one source.
    func workoutCount(from source: ConnectorSource) throws -> Int {
        try modelContext.fetchCount(Self.descriptor(for: source))
    }

    /// Ids of the cached workouts, newest first.
    func cachedWorkoutIDs() throws -> [String] {
        let descriptor = FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        return try modelContext.fetch(descriptor).map(\.id)
    }

    /// Deletes one source's workouts without saving.
    ///
    /// Fetch-then-delete rather than `modelContext.delete(model:where:)`: the
    /// batch form bypasses the object graph and leaves `Exercise`/`ExerciseSet`
    /// rows orphaned instead of honouring their `.cascade` rule. At ~360
    /// workouts per window the extra fetch is irrelevant.
    ///
    /// A failing fetch must propagate: swallowing it would let the caller
    /// insert a second copy of the window on top of the old one, and without
    /// `@Attribute(.unique)` on `Workout.id` every workout would then be
    /// cached twice while the sync still reports success.
    private func deleteWorkouts(from source: ConnectorSource) throws {
        for workout in try modelContext.fetch(Self.descriptor(for: source)) {
            modelContext.delete(workout)
        }
    }

    /// `#Predicate` cannot call into `ConnectorSource`, so the raw value is
    /// captured before the macro sees it.
    private static func descriptor(for source: ConnectorSource) -> FetchDescriptor<Workout> {
        let raw = source.rawValue
        return FetchDescriptor<Workout>(predicate: #Predicate { $0.sourceRawValue == raw })
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

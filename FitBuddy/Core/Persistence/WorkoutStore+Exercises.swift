import Foundation
import SwiftData

extension WorkoutStore: ExerciseSummaryReading {
    /// Movements performed inside the window, most recently performed first.
    ///
    /// Walks the same rows `workoutSummaries(since:)` does and folds them by
    /// movement instead of by session, so the two screens can never disagree
    /// about what a warm-up is worth: both go through
    /// `SetType.countsTowardsVolume`.
    ///
    /// The sort is by `lastPerformed` descending, ties broken by title, so the
    /// order is stable — SwiftData does not guarantee the order of a to-many
    /// relationship, and a list that reshuffles between two reads of the same
    /// cache would look like the data changed.
    func exerciseSummaries(since date: Date) throws -> [ExerciseSummary] {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startTime >= date },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]

        var summaries: [String: ExerciseSummary] = [:]
        for workout in try modelContext.fetch(descriptor) {
            // Per session, so a movement performed twice in one workout still
            // counts as one session for it.
            var keysInWorkout: Set<String> = []
            for exercise in workout.exercises {
                let key = ExerciseSummary.key(templateID: exercise.templateID, title: exercise.title)
                let countedSets = exercise.sets.filter { $0.type.countsTowardsVolume }
                let isNewSession = keysInWorkout.insert(key).inserted
                summaries[key] = merge(
                    summaries[key],
                    key: key,
                    exercise: exercise,
                    startTime: workout.startTime,
                    countedSets: countedSets,
                    countsAsSession: isNewSession
                )
            }
        }
        return summaries.values.sorted { lhs, rhs in
            guard lhs.lastPerformed == rhs.lastPerformed else {
                return lhs.lastPerformed > rhs.lastPerformed
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    /// Folds one occurrence into the running summary for its movement.
    ///
    /// The title and the muscle group come from the first occurrence seen,
    /// which is the most recent one because the fetch is sorted newest first:
    /// a renamed exercise shows the name the user last used, not the one they
    /// moved away from.
    ///
    /// Must be called on the actor owning `exercise`.
    private func merge(
        _ existing: ExerciseSummary?,
        key: String,
        exercise: Exercise,
        startTime: Date,
        countedSets: [ExerciseSet],
        countsAsSession: Bool
    ) -> ExerciseSummary {
        guard let existing else {
            return ExerciseSummary(
                id: key,
                title: exercise.title,
                muscleGroup: MuscleGroup.from(exerciseTitle: exercise.title),
                sessionCount: countsAsSession ? 1 : 0,
                countedSetCount: countedSets.count,
                volumeKg: countedSets.trainingVolumeKg,
                lastPerformed: startTime
            )
        }
        return ExerciseSummary(
            id: existing.id,
            title: existing.title,
            muscleGroup: existing.muscleGroup,
            sessionCount: existing.sessionCount + (countsAsSession ? 1 : 0),
            countedSetCount: existing.countedSetCount + countedSets.count,
            volumeKg: existing.volumeKg + countedSets.trainingVolumeKg,
            lastPerformed: max(existing.lastPerformed, startTime)
        )
    }
}

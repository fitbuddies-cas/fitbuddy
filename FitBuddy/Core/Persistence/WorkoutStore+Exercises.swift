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
    ///
    /// Endurance sessions stay out (US-5 AC1, US-9): a run is mapped to one
    /// "exercise" named after the sport with a single cardio set, and listed
    /// it would read as a movement with 0 kg over n sessions, carry a guessed
    /// muscle group, and merge with a Hevy exercise of the same title. The
    /// exercise list is the strength picture, like the muscle split in
    /// `WorkoutSummary`.
    ///
    /// Which sessions those are is decided by `WorkoutSummary.isCardio` since
    /// #183 — the same rule `AnalysisDomain` and the prompt's sections read —
    /// and no longer by the source. The two disagree in both directions, and
    /// each disagreement put the Exercises section out of step with the
    /// strength sections it is supposed to describe: a Hevy treadmill session
    /// was listed as a movement although its session sits in the endurance
    /// section, and a Strava `WeightTraining` session never appeared here
    /// although the strength figures count it. Rule 6 of the system prompt
    /// tells the model to recommend only on this section, so a mismatch is a
    /// recommendation grounded in something the prompt did not state.
    ///
    /// The filter therefore runs in memory rather than in the predicate:
    /// `isCardio` reads the sets of a workout, which `#Predicate` cannot. The
    /// rows are walked anyway to fold the movements, and `WorkoutSummary`
    /// gives the one verdict the whole feature shares.
    func exerciseSummaries(since date: Date) throws -> [ExerciseSummary] {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startTime >= date },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]

        var summaries: [String: ExerciseSummary] = [:]
        for workout in try modelContext.fetch(descriptor) where !WorkoutSummary(workout: workout).isCardio {
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

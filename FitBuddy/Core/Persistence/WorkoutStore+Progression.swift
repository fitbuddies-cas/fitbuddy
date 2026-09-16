import Foundation
import SwiftData

extension WorkoutStore: ExerciseProgressionReading {
    /// Every session of this movement in the window, oldest first, with all the
    /// sets it was logged with — the history (#163) and, derived from it, the
    /// curve (US-9 AC1).
    ///
    /// Walks the same rows the exercise list walks and folds them by session
    /// instead of by movement, so the two screens agree on what a session is
    /// and on which sets count: warm-ups are excluded here as well, because a
    /// ramp-up set would otherwise define the day's best on a light session.
    ///
    /// Strava and Polar sessions are skipped for the same reason the list skips them:
    /// a run has no weight and no reps, so it could only ever contribute an
    /// empty curve — or, sharing a title with a Hevy movement, a title.
    func exerciseProgression(id: String, since date: Date) throws -> ExerciseProgression? {
        let enduranceSources = ConnectorSource.allCases.filter(\.isEnduranceSource).map(\.rawValue)
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startTime >= date && !enduranceSources.contains($0.sourceRawValue) },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]

        var sessions: [ExerciseHistoryEntry] = []
        var title: String?

        for workout in try modelContext.fetch(descriptor) {
            let occurrences = workout.exercises.filter {
                ExerciseSummary.key(templateID: $0.templateID, title: $0.title) == id
            }
            guard !occurrences.isEmpty else { continue }

            // The fetch is sorted ascending, so the last matching session wins
            // by overwriting: the title follows the most recent session, as in
            // the list — a renamed movement shows the name the user last used.
            title = occurrences.last?.title

            // Across every occurrence of the movement in this session, so a
            // workout that lists it twice still yields one entry. Sorted by
            // index, as the card inside a session does: SwiftData does not
            // guarantee the order of a to-many relationship, and set numbers
            // that disagree with the order the user lifted in are worse than
            // no numbers.
            let sets = occurrences
                .flatMap(\.sets)
                .sorted { $0.index < $1.index }
                .map(SetDetail.init(set:))

            sessions.append(
                ExerciseHistoryEntry(
                    workoutID: workout.id,
                    sessionStart: workout.startTime,
                    sets: sets
                )
            )
        }

        guard let title else { return nil }
        return ExerciseProgression(id: id, title: title, sessions: sessions)
    }
}

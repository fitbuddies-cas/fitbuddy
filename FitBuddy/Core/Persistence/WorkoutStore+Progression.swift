import Foundation
import SwiftData

extension WorkoutStore: ExerciseProgressionReading {
    /// One point per session that carried a usable set of this movement,
    /// oldest first (US-9 AC1).
    ///
    /// Walks the same rows the exercise list walks and folds them by session
    /// instead of by movement, so the two screens agree on what a session is
    /// and on which sets count: warm-ups are excluded here as well, because a
    /// ramp-up set would otherwise define the day's best on a light session.
    func exerciseProgression(id: String, since date: Date) throws -> ExerciseProgression? {
        var descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { $0.startTime >= date },
            sortBy: [SortDescriptor(\.startTime, order: .forward)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [\.exercises]

        var points: [ProgressionPoint] = []
        var title: String?
        var titleDate: Date?

        for workout in try modelContext.fetch(descriptor) {
            let occurrences = workout.exercises.filter {
                ExerciseSummary.key(templateID: $0.templateID, title: $0.title) == id
            }
            guard !occurrences.isEmpty else { continue }

            // The title follows the most recent session, as in the list: a
            // renamed movement shows the name the user last used.
            if titleDate == nil || workout.startTime >= titleDate! {
                title = occurrences.last?.title
                titleDate = workout.startTime
            }

            // Across every occurrence of the movement in this session, so a
            // workout that lists it twice still yields one point.
            let best = occurrences
                .flatMap(\.sets)
                .filter { $0.type.countsTowardsVolume }
                .compactMap { set -> ProgressionPoint? in
                    guard let estimate = OneRepMax.epley(of: set),
                          let weightKg = set.weightKg,
                          let reps = set.reps else { return nil }
                    return ProgressionPoint(
                        sessionStart: workout.startTime,
                        estimatedOneRepMaxKg: estimate,
                        weightKg: weightKg,
                        reps: reps
                    )
                }
                .max { $0.estimatedOneRepMaxKg < $1.estimatedOneRepMaxKg }

            if let best { points.append(best) }
        }

        guard let title else { return nil }
        return ExerciseProgression(id: id, title: title, points: points)
    }
}

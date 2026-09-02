import Foundation

/// One exercise of a workout with its logged sets — the `Sendable` projection
/// the detail screen renders a card from (#98).
///
/// Carries its own volume and counted-set totals rather than letting the view
/// add them up: the warm-up rule lives in `SetType.countsTowardsVolume`, and a
/// second implementation of it in a `body` would be the place where the card
/// and the dashboard start disagreeing about the same session.
struct ExerciseDetail: Equatable, Identifiable, Sendable {
    /// Position of the exercise within its workout, as ordered in Hevy.
    let index: Int
    let title: String
    /// The user's note on this exercise, if they wrote one.
    let notes: String?
    /// Hevy's superset grouping id; `nil` when the exercise stands alone.
    let supersetID: Int?
    /// Derived from the title, like everywhere else in the app — v0 does not
    /// fetch Hevy's exercise templates (see `MuscleGroup`).
    let muscleGroup: MuscleGroup
    /// The logged sets, in Hevy's order.
    let sets: [SetDetail]
    /// Σ (weight × reps) over the counted sets, in kg.
    let volumeKg: Double
    /// Sets that counted towards `volumeKg` (warm-ups excluded).
    let countedSetCount: Int

    var id: Int { index }
}

extension ExerciseDetail {
    /// Reduces a cached exercise, sorting its sets by `index`.
    ///
    /// The sort is not cosmetic: SwiftData does not guarantee the order of a
    /// to-many relationship, so without it the set numbers on screen could
    /// disagree with the order the user actually lifted in.
    ///
    /// Must be called on the actor owning `exercise`.
    init(exercise: Exercise) {
        let sets = exercise.sets.sorted { $0.index < $1.index }
        let countedSets = sets.filter { $0.type.countsTowardsVolume }

        self.init(
            index: exercise.index,
            title: exercise.title,
            notes: exercise.notes,
            supersetID: exercise.supersetID,
            muscleGroup: MuscleGroup.from(exerciseTitle: exercise.title),
            sets: sets.map(SetDetail.init(set:)),
            volumeKg: ExerciseSet.volume(of: countedSets),
            countedSetCount: countedSets.count
        )
    }
}

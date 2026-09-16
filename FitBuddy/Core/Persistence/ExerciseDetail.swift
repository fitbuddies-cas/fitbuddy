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
    /// The source's own identifier for the movement, stable across sessions
    /// (Hevy's `exercise_template_id`). Carried so a card can open the
    /// movement's statistics under the same identity the exercise list uses
    /// (#162) — see `ExerciseIdentity`.
    let templateID: String?
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
    /// Builds an exercise from its sets and derives everything that follows
    /// from them: the muscle group, the volume and the counted-set tally.
    ///
    /// The deriving initialiser is the only one anything outside this file
    /// should reach for — a caller that passes its own totals is a caller that
    /// can get them wrong, which is exactly how previews and fixtures drift
    /// away from what the app would show.
    init(
        index: Int,
        title: String,
        notes: String? = nil,
        templateID: String? = nil,
        supersetID: Int? = nil,
        sets: [SetDetail]
    ) {
        let countedSets = sets.filter(\.countsTowardsVolume)

        self.init(
            index: index,
            title: title,
            notes: notes,
            templateID: templateID,
            supersetID: supersetID,
            muscleGroup: MuscleGroup.from(exerciseTitle: title),
            sets: sets,
            volumeKg: countedSets.trainingVolumeKg,
            countedSetCount: countedSets.count
        )
    }

    /// The sets paired with their number among the counted ones, so a list
    /// reads "W, 1, 2, 3" the way the app tallies them — not "1, 2, 3, 4" with
    /// the warm-up quietly claiming a working set's place.
    ///
    /// `nil` for every set outside the volume, which is more than the warm-ups:
    /// `SetType.countsTowardsVolume` also excludes `.unknown`, and that is
    /// where a missing `type` and every type a later Hevy adds end up. It lives
    /// here rather than in the card so that numbering a set and marking it come
    /// from one rule — deriving them separately is what once gave a leading
    /// unknown set the number 0.
    var numberedSets: [(set: SetDetail, number: Int?)] {
        var number = 0
        return sets.map { set in
            guard set.countsTowardsVolume else { return (set, nil) }
            number += 1
            return (set, number)
        }
    }

    /// Reduces a cached exercise, sorting its sets by `index`.
    ///
    /// The sort is not cosmetic: SwiftData does not guarantee the order of a
    /// to-many relationship, so without it the set numbers on screen could
    /// disagree with the order the user actually lifted in.
    ///
    /// Must be called on the actor owning `exercise`.
    init(exercise: Exercise) {
        self.init(
            index: exercise.index,
            title: exercise.title,
            notes: exercise.notes,
            templateID: exercise.templateID,
            supersetID: exercise.supersetID,
            sets: exercise.sets
                .sorted { $0.index < $1.index }
                .map(SetDetail.init(set:))
        )
    }
}

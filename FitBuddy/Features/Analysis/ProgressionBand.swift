import Foundation

/// The load range a progression may move an exercise to (ADR-013, #232).
///
/// A ceiling in percent of the working weight, tiered by muscle group, and
/// a floor of one equipment step. The prompt names the range per exercise
/// and the report validation (#233) checks a progression card against the
/// same range, so both read it from here.
///
/// The percentages come from the 2–10 % corridor of ADR-013; the cut at 5 %
/// for small groups and the filing of `core` and `other` under it are set
/// there, not derived. Nothing here is validated on FitBuddy's users, and no
/// prompt or screen may say otherwise.
enum ProgressionBand {
    /// The ceiling for the large groups: legs, back, chest.
    static let largeGroupShare = 0.10
    /// The ceiling for the small groups — and for `other`, which is what the
    /// title heuristic could not classify and therefore gets the cautious
    /// limit, not the generous one.
    static let smallGroupShare = 0.05

    /// The share of the working weight the ceiling sits at for `group`.
    static func share(for group: MuscleGroup) -> Double {
        switch group {
        case .legs, .back, .chest:
            return largeGroupShare
        case .shoulders, .arms, .core, .other:
            return smallGroupShare
        }
    }

    /// The step the exercise's range is rounded to — the granularity #173 and
    /// #175 fixed, unchanged by the band: 2.5 kg for a barbell exercise, the
    /// smallest logged step for anything else, and none where none was
    /// logged, which is where reps are the lever (#234).
    static func stepKg(for exercise: ListedExercise) -> Double? {
        if AnalysisPromptBuilder.isBarbell(title: exercise.title) {
            return AnalysisPromptBuilder.minimumStepKg
        }
        return exercise.smallestStepKg
    }

    /// The range for a listed exercise, or `nil` when it has no working
    /// weight to start from or no step to move by.
    ///
    /// Only the numbers: whether a progression is *allowed* at all is the
    /// 2-for-2 rule's call (`TwoForTwoCondition`), read separately, so a
    /// caller that wants to say "the range would be X, but the condition is
    /// not met" can.
    static func range(for exercise: ListedExercise) -> ClosedRange<Double>? {
        guard let working = exercise.workingSet?.roundedWeightKg,
              let step = stepKg(for: exercise)
        else { return nil }
        return range(workingKg: working, stepKg: step, group: exercise.muscleGroup)
    }

    /// The range from `workingKg` in steps of `stepKg` under `group`'s
    /// ceiling: one step up to the largest multiple of the step that stays at
    /// or under the ceiling.
    ///
    /// One step is always allowed, whatever the ceiling says (ADR-013,
    /// decision 2): on a light exercise the ceiling can sit below a single
    /// step, and forbidding the smallest possible increase would be
    /// equipment granularity through the back door. The range is then that
    /// one step — the behaviour before the band, which was right for those
    /// exercises.
    static func range(workingKg: Double, stepKg: Double, group: MuscleGroup) -> ClosedRange<Double> {
        let lower = PlainWeightFormatter.rounded(workingKg + stepKg)
        let ceiling = workingKg * (1 + share(for: group))
        // A hair of tolerance, so 66 / 2.5 does not floor to 1 because of a
        // floating-point 2.3999.
        let steps = floor((ceiling - workingKg) / stepKg + 1e-9)
        let upper = PlainWeightFormatter.rounded(workingKg + max(1, steps) * stepKg)
        return lower...max(lower, upper)
    }

    /// The range as the prompt writes it: "62.5–65 kg", or "12 kg" where the
    /// range is a single step.
    static func text(_ range: ClosedRange<Double>) -> String {
        let lower = PlainWeightFormatter.string(range.lowerBound)
        let upper = PlainWeightFormatter.string(range.upperBound)
        return lower == upper ? "\(lower) kg" : "\(lower)–\(upper) kg"
    }
}

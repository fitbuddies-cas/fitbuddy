import Foundation

/// A set that carries a working weight: counted towards volume, with both a
/// weight and reps logged (#173).
///
/// The value a load recommendation starts from. The analysis prompt lists it
/// per exercise, and the validator of #175 checks a card's starting weight
/// against it — so what qualifies, and which one counts as *the* working set
/// of a session, is decided here once.
struct WorkingSet: Equatable, Sendable {
    let weightKg: Double
    let reps: Int

    /// The weight as the prompt writes it — see `PlainNumberFormatter`.
    var weightText: String { PlainNumberFormatter.string(weightKg) }

    /// The weight at the precision the prompt states it, for comparing a
    /// figure read back from the model's answer.
    var roundedWeightKg: Double { PlainNumberFormatter.rounded(weightKg) }

    /// Whether this set is the heavier of the two: by weight, ties broken by
    /// reps. By weight rather than by Epley, because a recommendation moves
    /// the weight on the bar — 65 kg × 3 is the working weight even where
    /// 60 kg × 8 projects the higher 1RM.
    func isHeavier(than other: WorkingSet) -> Bool {
        weightKg != other.weightKg ? weightKg > other.weightKg : reps > other.reps
    }
}

extension WorkingSet {
    /// The working set a logged set stands for, or `nil` when it is none.
    ///
    /// Warm-ups do not qualify, and neither do sets missing weight or reps: a
    /// bodyweight set has no load to start from, a loaded carry logs weight
    /// and distance but no reps, and a set started but not completed (0 reps)
    /// was not lifted — the same guard `OneRepMax` applies.
    init?(set: SetDetail) {
        guard set.countsTowardsVolume,
              let weightKg = set.weightKg, weightKg > 0,
              let reps = set.reps, reps > 0
        else { return nil }
        self.init(weightKg: weightKg, reps: reps)
    }
}

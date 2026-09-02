import Foundation

extension ExerciseSet {
    /// Σ (weight × reps) over `sets`, in kg.
    ///
    /// A set contributes only with both numbers present: a bodyweight or
    /// cardio set has no kg volume, and treating its missing weight as 0 would
    /// be the same result with a worse intent.
    ///
    /// Filtering by `type.countsTowardsVolume` is the caller's job — the
    /// dashboard sums a whole window, the detail screen one exercise, and both
    /// have already narrowed the sets down by then.
    static func volume(of sets: [ExerciseSet]) -> Double {
        sets.reduce(0) { total, set in
            guard let weight = set.weightKg, let reps = set.reps else { return total }
            return total + weight * Double(reps)
        }
    }
}

import Foundation

/// A logged set seen through the two numbers that make training volume.
///
/// Both the cached `ExerciseSet` and its `SetDetail` projection carry them, and
/// the dashboard, the detail screen and the previews all have to agree on what
/// a set contributes. Writing Σ (weight × reps) out per call site is how a
/// header ends up contradicting the cards under it — so the rule lives here
/// once, for whichever of the two types a caller happens to hold.
protocol VolumeContributing {
    var weightKg: Double? { get }
    var reps: Int? { get }
}

extension ExerciseSet: VolumeContributing {}

extension SetDetail: VolumeContributing {}

extension Sequence where Element: VolumeContributing {
    /// Σ (weight × reps) over the sets, in kg.
    ///
    /// A set contributes only with both numbers present: a bodyweight or
    /// cardio set has no kg volume, and treating its missing weight as 0 would
    /// be the same result with a worse intent.
    ///
    /// Filtering by `SetType.countsTowardsVolume` is the caller's job — the
    /// dashboard sums a whole window, the detail screen one exercise, and both
    /// have already narrowed the sets down by then.
    var trainingVolumeKg: Double {
        reduce(0) { total, set in
            guard let weight = set.weightKg, let reps = set.reps else { return total }
            return total + weight * Double(reps)
        }
    }
}

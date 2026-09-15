import Foundation

/// Estimates a one-rep maximum from a logged set (US-9 AC1, #41).
///
/// Epley: `weight × (1 + reps / 30)`. The formula is an estimate, not a
/// measurement — it is what makes two sets at different rep counts comparable
/// at all, which is the whole point of a progression curve: 100 kg × 5 and
/// 80 kg × 12 say nothing to each other until both are expressed as the same
/// number.
///
/// US-9 names Epley specifically, so the choice is the requirement's rather
/// than ours. Worth knowing where it is weak: above roughly ten reps it
/// overestimates, because it assumes a linear trade between load and
/// repetitions that muscular endurance does not follow. The curve therefore
/// tracks *change* honestly while the absolute number stays a projection.
enum OneRepMax {
    /// The estimate for one set, or `nil` when the set does not carry the two
    /// numbers the formula needs.
    ///
    /// - Returns: `nil` for a set without weight or reps — a bodyweight or
    ///   cardio set has no load to project from, and substituting a zero would
    ///   turn "not logged" into "lifted nothing". `nil` as well for a set that
    ///   was started but not completed (0 reps): the formula would hand back
    ///   the bare weight as if it had been lifted once.
    static func epley(weightKg: Double?, reps: Int?) -> Double? {
        guard let weightKg, let reps, weightKg > 0, reps > 0 else { return nil }
        return weightKg * (1 + Double(reps) / 30)
    }

    /// The estimate for a whole set, read through the same two numbers volume
    /// is read through.
    static func epley(of set: some VolumeContributing) -> Double? {
        epley(weightKg: set.weightKg, reps: set.reps)
    }
}

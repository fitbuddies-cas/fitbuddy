import Foundation

/// Remembers which analysis profile the user last ran (US-15 AC1, #185).
///
/// `UserDefaults` and a single scalar, like `LLMPriorityStore` and
/// `TrainingProfileStore`: the choice is a preference, not health data, and it
/// must not outlive an app deletion. An `actor` for the same reason as those
/// two — the reset path clears it off the main actor.
///
/// Deliberately *not* stored with the analysis history. The row records which
/// profile produced it (`AnalysisResult.analysisProfileRawValue`), which is a
/// fact about that run; this is the user's standing preference, and a deleted
/// history must not take it with it.
actor AnalysisProfileStore {
    static let profileKey = "fitbuddy.analysis.profile"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The last profile the user analysed with, or `nil` before their first
    /// run — and for a value this build has no case for, where falling back to
    /// the computed default is better than guessing at what was meant.
    var profile: AnalysisProfile? {
        defaults.string(forKey: Self.profileKey).flatMap(AnalysisProfile.init(rawValue:))
    }

    func save(_ profile: AnalysisProfile) {
        defaults.set(profile.rawValue, forKey: Self.profileKey)
    }

    /// "Delete all data": the next analysis starts from the default its data
    /// suggests, not from a choice made about training that is gone.
    func clear() {
        defaults.removeObject(forKey: Self.profileKey)
    }
}

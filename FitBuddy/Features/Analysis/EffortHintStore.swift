import Foundation

/// Remembers that the result screen has shown its one-time effort hint
/// (#245, US-18 AC6).
///
/// The hint tells a user who records no effort anywhere that the analysis gets
/// more precise with it — **once**, never again after that, and without a
/// dialog or a question about past sessions. The flag is what makes "once"
/// hold across runs and app restarts.
///
/// `UserDefaults` and a single flag, like `AnalysisProfileStore`: a UI
/// preference, not health data. An `actor` for the same reason as the other
/// stores — the reset path clears it off the main actor.
actor EffortHintStore {
    static let shownKey = "fitbuddy.analysis.effortHintShown"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the hint has been shown on this install.
    var hasShownHint: Bool {
        defaults.bool(forKey: Self.shownKey)
    }

    /// Records that the hint has been shown, so it is never shown again.
    func markShown() {
        defaults.set(true, forKey: Self.shownKey)
    }

    /// "Delete all data": the install starts over, hint included.
    func clear() {
        defaults.removeObject(forKey: Self.shownKey)
    }
}

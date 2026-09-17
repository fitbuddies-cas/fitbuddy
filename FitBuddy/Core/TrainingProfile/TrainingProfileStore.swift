import Foundation

/// Persists the training profile and the decision not to give one (US-13).
///
/// `UserDefaults`, not the Keychain: a training goal is not a secret, and like
/// the step-3 skip marker the decision must not outlive an app deletion. An
/// `actor` like the other `UserDefaults`-backed stores, so the reset path can
/// clear it off the main actor.
actor TrainingProfileStore {
    static let goalKey = "fitbuddy.trainingProfile.goal"
    static let experienceKey = "fitbuddy.trainingProfile.experience"
    /// Set when the user skipped the step, so it does not reappear on every
    /// cold start (AC2).
    static let skippedKey = "fitbuddy.trainingProfile.skipped"
    /// Records that this install has seen the version introducing the step.
    ///
    /// The discriminator between "has not answered yet" and "was never asked".
    /// Without it, every user who finished onboarding before this step existed
    /// would be sent back into it on the next launch — see
    /// `OnboardingViewModel`, which writes this marker once and treats an
    /// already-complete install as having skipped.
    static let introducedKey = "fitbuddy.trainingProfile.stepIntroduced"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Profile

    var profile: TrainingProfile {
        TrainingProfile(
            goal: defaults.string(forKey: Self.goalKey).flatMap(TrainingGoal.init(rawValue:)),
            experience: defaults.string(forKey: Self.experienceKey)
                .flatMap(TrainingExperience.init(rawValue:))
        )
    }

    /// Writes the profile, removing whichever half was left unanswered.
    ///
    /// Removing rather than leaving the previous value behind: a user who
    /// clears their goal in Settings means it to be gone, and a stale entry
    /// would keep reaching the prompt (#191).
    func save(_ profile: TrainingProfile) {
        write(profile.goal?.rawValue, forKey: Self.goalKey)
        write(profile.experience?.rawValue, forKey: Self.experienceKey)
    }

    /// Drops the profile, leaving the skip decision as it is — removing the
    /// answers is not the same as asking the question again.
    func clearProfile() {
        defaults.removeObject(forKey: Self.goalKey)
        defaults.removeObject(forKey: Self.experienceKey)
    }

    // MARK: - Decisions

    var isSkipped: Bool {
        defaults.bool(forKey: Self.skippedKey)
    }

    func setSkipped() {
        defaults.set(true, forKey: Self.skippedKey)
    }

    /// Whether the user has settled the step either way — answered something,
    /// or said no. What `OnboardingViewModel` asks before showing step 4.
    var isDecided: Bool {
        !profile.isEmpty || isSkipped
    }

    var hasSeenIntroduction: Bool {
        defaults.bool(forKey: Self.introducedKey)
    }

    func markIntroductionSeen() {
        defaults.set(true, forKey: Self.introducedKey)
    }

    /// Drops profile and skip decision ("delete all data"), so onboarding asks
    /// again.
    ///
    /// Keeps the introduction marker, for the reason `DataResetService` keeps
    /// `FirstLaunchResetService`'s: it records the installation, not the
    /// session. Clearing it would make the next launch treat this install as a
    /// pre-update one and skip the step for good.
    func clear() {
        clearProfile()
        defaults.removeObject(forKey: Self.skippedKey)
    }

    private func write(_ value: String?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }
}

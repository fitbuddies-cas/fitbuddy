import Foundation

/// Persists the user's "skip for now" decision on onboarding step 3 (US-4 AC2)
/// so the LLM key screen does not reappear on every cold start.
///
/// `UserDefaults`, not the Keychain: unlike a key, the decision must not
/// outlive an app deletion — the same reasoning `FirstLaunchResetService`
/// applies to its own marker. An `actor` like the other `UserDefaults`-backed
/// stores (`LLMPriorityStore`, `SyncTimestampStore`), so the reset path can
/// clear it off the main actor.
actor LLMKeysSkipStore {
    /// `UserDefaults` key holding the skip marker.
    static let skippedKey = "fitbuddy.onboarding.llmKeysSkipped"

    /// Name this marker had while step 3 took a single Claude key. Existing
    /// testers who skipped back then still carry it, so it is read as a
    /// fallback and migrated forward once — without it, their decision would be
    /// lost on update and step 3 would reappear.
    static let legacySkippedKey = "fitbuddy.onboarding.claudeKeySkipped"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the user already chose to continue without an LLM key. Honors
    /// the pre-multi-provider marker and migrates it forward on the way, so
    /// the stale entry does not linger.
    var isSkipped: Bool {
        if defaults.bool(forKey: Self.skippedKey) { return true }
        guard defaults.bool(forKey: Self.legacySkippedKey) else { return false }
        setSkipped()
        return true
    }

    func setSkipped() {
        defaults.set(true, forKey: Self.skippedKey)
        defaults.removeObject(forKey: Self.legacySkippedKey)
    }

    /// Drops the marker ("delete all data"), so onboarding asks for LLM keys
    /// again. Clears the legacy key too — left behind, it would migrate itself
    /// forward on the next bootstrap and silently skip step 3 again.
    func clear() {
        defaults.removeObject(forKey: Self.skippedKey)
        defaults.removeObject(forKey: Self.legacySkippedKey)
    }
}

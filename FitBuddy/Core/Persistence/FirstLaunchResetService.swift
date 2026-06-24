import Foundation

/// Ensures a fresh install starts from a clean state.
///
/// Keychain items survive app deletion on iOS, so a reinstall would otherwise
/// inherit the previous install's consent and API keys. `UserDefaults`, by
/// contrast, is wiped on deletion — so a missing marker means "first launch
/// after install". On that first launch we purge all Keychain items and set the
/// marker, coupling the Keychain lifetime to the app installation.
actor FirstLaunchResetService {
    private static let didResetKey = "fitbuddy.firstLaunchReset.completed"

    private let defaults: UserDefaults
    private let keychain: KeychainService

    init(defaults: UserDefaults = .standard, keychain: KeychainService = KeychainService()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    /// Purges all Keychain items on the first launch after install, then marks
    /// the reset as done; a no-op once the marker is set.
    ///
    /// The purge runs before the marker is written, so the two steps are not
    /// atomic: a process kill in between simply re-runs the (idempotent) purge
    /// on the next launch. This order is deliberate — the alternative (marker
    /// first) could leave stale Keychain items if interrupted.
    func resetIfFirstLaunch() async throws {
        guard !defaults.bool(forKey: Self.didResetKey) else { return }

        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
        defaults.set(true, forKey: Self.didResetKey)
    }
}

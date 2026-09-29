import Foundation

/// Ensures a fresh install starts from a clean state.
///
/// Keychain items survive app deletion on iOS, so a reinstall would otherwise
/// inherit the previous install's consent and API keys. `UserDefaults`, by
/// contrast, is wiped on deletion — so a missing marker means "first launch
/// after install". On that first launch we purge all Keychain items and set the
/// marker, coupling the Keychain lifetime to the app installation.
///
/// A UI test needs that same clean slate on demand rather than once per
/// install — see `resetLaunchArgument`.
actor FirstLaunchResetService {
    private static let didResetKey = "fitbuddy.firstLaunchReset.completed"

    #if DEBUG
    /// DEBUG-only launch argument that makes this launch behave like the first
    /// one after an install, whatever the marker says (#120).
    ///
    /// The UI tests need it because a simulator keeps both halves of the state
    /// this service exists to reconcile: the Keychain survives an app
    /// deletion, and `UserDefaults` survives a relaunch. Without it the first
    /// test to complete onboarding would leave every later one starting on the
    /// dashboard.
    static let resetLaunchArgument = "-fbResetState"
    #endif

    private let defaults: UserDefaults
    private let keychain: KeychainService
    private let launchArguments: [String]
    /// The defaults domain a forced reset clears — the app's own bundle id in
    /// production, a suite name in tests.
    private let domainName: String?

    init(
        defaults: UserDefaults = .standard,
        keychain: KeychainService = KeychainService(),
        launchArguments: [String] = LaunchArguments.current,
        domainName: String? = Bundle.main.bundleIdentifier
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.launchArguments = launchArguments
        self.domainName = domainName
    }

    /// Purges all Keychain items on the first launch after install, then marks
    /// the reset as done; a no-op once the marker is set.
    ///
    /// The purge runs before the marker is written, so the two steps are not
    /// atomic: a process kill in between simply re-runs the (idempotent) purge
    /// on the next launch. This order is deliberate — the alternative (marker
    /// first) could leave stale Keychain items if interrupted.
    func resetIfFirstLaunch() async throws {
        let isForced = isForcedReset
        guard isForced || !defaults.bool(forKey: Self.didResetKey) else { return }

        if isForced {
            // A real first launch starts with empty `UserDefaults`; a forced one
            // does not, so the markers a reinstall would have taken with it —
            // the step-3 skip, the provider order, the sync timestamp — are
            // cleared explicitly. This drops `didResetKey` too, which the write
            // below restores.
            domainName.map(defaults.removePersistentDomain(forName:))
        }

        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
        defaults.set(true, forKey: Self.didResetKey)
    }

    private var isForcedReset: Bool {
        #if DEBUG
        return launchArguments.contains(Self.resetLaunchArgument)
        #else
        return false
        #endif
    }
}

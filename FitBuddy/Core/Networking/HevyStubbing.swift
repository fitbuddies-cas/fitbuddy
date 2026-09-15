import Foundation

// Test support: excluded from Release builds, so a shipped binary has no way
// to reach the stubs behind it.
#if DEBUG

/// The DEBUG-only seam that lets a UI test walk the real app without a real
/// API key and without a single network call (#120).
///
/// One launch argument rather than one per collaborator, because "this launch
/// must not talk to Hevy" is a single decision: a stubbed key check that still
/// let the dashboard sync would send the user straight back to step 2 on the
/// 401, which is precisely what the happy-path test would then be watching.
///
/// `-fbStubHevy accepts` walks onboarding to the end; `-fbStubHevy rejects`
/// makes step 2 fail the way a revoked key does. Without the argument nothing
/// here is consulted and the app builds its live collaborators.
enum HevyStubbing {
    static let launchArgument = "-fbStubHevy"

    /// Makes the stubbed sync take a few seconds instead of returning at once,
    /// so a pull-to-refresh ends its gesture while the sync is still running —
    /// the window in which #150 showed. Used by `DashboardRefreshUITests`; the
    /// onboarding UI tests leave it off.
    static let slowSyncLaunchArgument = "-fbSlowStubSync"

    static func slowSyncIsActive(in launchArguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        launchArguments.contains(slowSyncLaunchArgument)
    }

    /// Makes the stubbed sync write the bundled mock workouts (#44) into the
    /// cache, so a stubbed launch reaches the loaded dashboard instead of the
    /// empty state. Used by `DashboardRefreshUITests`; the onboarding UI tests
    /// leave it off.
    static let seedMockWorkoutsLaunchArgument = "-fbSeedMockWorkouts"

    static func seedsMockWorkouts(in launchArguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        launchArguments.contains(seedMockWorkoutsLaunchArgument)
    }

    /// Whether this launch replaces every Hevy collaborator with a stub.
    ///
    /// Derived from the verdict rather than from the argument's presence: read
    /// separately, `-fbStubHevy accpets` would stub the sync but leave the
    /// validator live — real key checks against Hevy behind a dashboard that
    /// never syncs. A typo has to leave *every* collaborator live.
    static func isActive(in launchArguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        verdict(in: launchArguments) != nil
    }

    /// The verdict for the key check, read from the value after the argument.
    ///
    /// An unknown or missing value yields `nil`, which the callers read as "do
    /// not stub" — a typo can then not silently turn a demo run into a stubbed
    /// one.
    static func verdict(
        in launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) -> StubHevyKeyValidator.Verdict? {
        guard let flag = launchArguments.firstIndex(of: launchArgument) else { return nil }
        let value = launchArguments.index(after: flag)
        guard value < launchArguments.endIndex else { return nil }
        return StubHevyKeyValidator.Verdict(rawValue: launchArguments[value])
    }
}

#endif

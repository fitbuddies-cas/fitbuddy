import Foundation

/// Mirror of the app's DEBUG-only launch arguments —
/// `FirstLaunchResetService.resetLaunchArgument` and
/// `HevyStubbing.launchArgument`.
///
/// Same reason as `AccessibilityID`: the UI test drives the app from another
/// process and cannot import the app module, so the strings exist twice. As
/// constants rather than literals there is one place to change per side, and a
/// rename on only one side fails the tests instead of silently launching an
/// unstubbed app.
enum LaunchArgument {
    /// Makes the launch behave like the first one after an install.
    static let resetState = "-fbResetState"
    /// Replaces every Hevy collaborator with a stub; takes a verdict.
    static let stubHevy = "-fbStubHevy"
    /// Skips onboarding altogether (`OnboardingViewModel.skipLaunchArgument`).
    static let skipOnboarding = "-fbSkipOnboarding"
    /// Makes the stubbed sync take a few seconds (`HevyStubbing`).
    static let slowStubSync = "-fbSlowStubSync"
    /// Makes the stubbed sync cache the bundled mock workouts (`HevyStubbing`).
    static let seedMockWorkouts = "-fbSeedMockWorkouts"

    enum Verdict {
        static let accepts = "accepts"
        static let rejects = "rejects"
    }
}

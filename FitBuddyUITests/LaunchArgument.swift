import Foundation

/// Mirror of the app's DEBUG-only launch arguments —
/// `FirstLaunchResetService.resetLaunchArgument`,
/// `HevyStubbing.launchArgument` and the mock seeders'.
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
    /// Skips onboarding altogether (`OnboardingViewModel.skipLaunchArgument`);
    /// no keys are stored afterwards.
    static let skipOnboarding = "-fbSkipOnboarding"
    /// Makes the stubbed sync take a few seconds (`HevyStubbing`).
    static let slowStubSync = "-fbSlowStubSync"
    /// Makes the stubbed sync cache the bundled mock workouts (`HevyStubbing`).
    static let seedMockWorkouts = "-fbSeedMockWorkouts"
    /// Fills the cache from a bundled mock history; takes a profile
    /// (`MockDataSeeder.launchArgument`, #148).
    static let seedMockData = "-fbSeedMockData"
    /// Stores an analysis with a report, so the analysis tab restores its
    /// cards; takes a report name (`MockAnalysisSeeder.launchArgument`, #177,
    /// #179).
    static let seedAnalysis = "-fbSeedAnalysis"

    enum Verdict {
        static let accepts = "accepts"
        static let rejects = "rejects"
    }

    enum Profile {
        static let personA = "person-a"
        static let personB = "person-b"
        static let progressionReady = "progression-ready"
        static let overreached = "overreached"
    }

    /// The reports `seedAnalysis` can store (`MockAnalysisSeeder.reports`).
    enum Report {
        static let progress = "progress"
        static let recover = "recover"
        static let hold = "hold"
        static let thin = "thin"
    }
}

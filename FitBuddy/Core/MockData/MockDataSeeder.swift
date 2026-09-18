import Foundation
import OSLog
import SwiftData

// Test support: excluded from Release builds, so no mock training history can
// reach a TestFlight binary — the payloads themselves are stripped via
// EXCLUDED_SOURCE_FILE_NAMES (#44).
#if DEBUG

/// Fills the local cache from a bundled mock profile before the first screen
/// reads it (#148).
///
/// The seam the UI tests were missing. `StubWorkoutSync` (#120) keeps a test
/// launch off the network, but it caches nothing, so every screen past
/// onboarding sits on its empty state — the dashboard, the exercise list and
/// the progression curve are all unreachable for a test that has no data to
/// tap on. This writes a real window through the real mapping instead:
/// recorded payloads → the source's own DTO → `Activity` → `WorkoutStore`, the
/// same path a live sync takes, so a test walks over data shaped like the
/// data users have. Since #188 a profile may hold more than one source, and
/// each is written the way its own sync would write it.
///
/// `-fbSeedMockData person-a` (or `person-b`, `progression-ready`,
/// `overreached`, `runner`, `mixed`, `overreached-mixed`) turns it on; without
/// the argument nothing here runs.
enum MockDataSeeder {
    static let launchArgument = "-fbSeedMockData"

    private static let logger = Logger(subsystem: "ch.bfh.fitbuddy", category: "MockDataSeeder")

    /// The profile named after the argument, or `nil` when the launch did not
    /// ask for one — including for an unknown name, so a typo leaves the app
    /// on its real (empty) cache rather than on a silently different profile.
    static func requestedProfile(
        in launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) -> MockWorkoutProfile? {
        guard let flag = launchArguments.firstIndex(of: launchArgument) else { return nil }
        let value = launchArguments.index(after: flag)
        guard value < launchArguments.endIndex else { return nil }
        return MockWorkoutProfile(rawValue: launchArguments[value])
    }

    /// Runs `FirstLaunchResetService`'s forced reset when the launch asked for
    /// one, whatever path the app takes afterwards.
    ///
    /// The service's own hook sits in `ConsentViewModel.bootstrap()`, which a
    /// launch with `-fbSkipOnboarding` never reaches — so a test that combined
    /// the two arguments got a promise of a clean slate that nothing kept, and
    /// the next test to rely on it would have found out as a flake.
    static func resetStateIfRequested(
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        reset: FirstLaunchResetService = FirstLaunchResetService()
    ) async {
        guard launchArguments.contains(FirstLaunchResetService.resetLaunchArgument) else { return }
        do {
            try await reset.resetIfFirstLaunch()
        } catch {
            logger.error("Forced state reset failed: \(error, privacy: .public)")
        }
    }

    /// Replaces the cached window with the requested profile's, and dates the
    /// sync to now.
    ///
    /// The timestamp matters as much as the workouts: without it the sync
    /// strip claims "Never synced" over a full dashboard, which is a state no
    /// real launch produces and a confusing thing to write a test against.
    ///
    /// Failures are logged and swallowed. This is a development seam — an app
    /// that refused to launch because a fixture could not be decoded would be
    /// worse than one that comes up empty, and the test that needed the data
    /// fails on the next assertion either way.
    static func seedIfRequested(
        container: ModelContainer,
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        timestamps: SyncTimestampStore = SyncTimestampStore(),
        now: () -> Date = Date.init
    ) async {
        guard let profile = requestedProfile(in: launchArguments) else { return }
        do {
            // Re-anchored on the clock the sync is dated with, not on the
            // system one: a caller that seeds at a fixed instant and then reads
            // the cache as of that instant has to see the window it asked for.
            let loader = MockWorkoutLoader(now: now)
            let store = WorkoutStore(modelContainer: container)
            var seeded = 0
            // One call per source, because that is how a sync writes: the store
            // replaces one source's window and leaves the others alone, so a
            // mixed profile has to hand it its Hevy half and its Strava half
            // separately — seeding both under `.hevy` would label the runs as
            // Hevy sessions and break the context line they exist for (#188).
            for payload in profile.payloads {
                let activities = try loader.activities(for: profile, from: payload.source)
                try await store.replaceCachedWorkouts(from: payload.source, with: activities)
                seeded += activities.count
            }
            await timestamps.setLastSync(now())
            logger.debug("Seeded \(seeded, privacy: .public) mock workouts")
        } catch {
            logger.error("Seeding \(profile.rawValue, privacy: .public) failed: \(error, privacy: .public)")
        }
    }
}

#endif

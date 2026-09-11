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
/// recorded Hevy payloads → `HevyWorkoutDTO` → `Activity` → `WorkoutStore`, the
/// same path a live sync takes, so a test walks over data shaped like the
/// data users have.
///
/// `-fbSeedMockData person-a` (or `person-b`) turns it on; without the
/// argument nothing here runs.
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
            let loader = MockWorkoutLoader()
            let activities = try loader.page(for: profile).workouts.map { $0.makeActivity() }
            try await WorkoutStore(modelContainer: container).replaceCachedWorkouts(with: activities)
            await timestamps.setLastSync(now())
            logger.debug("Seeded \(activities.count, privacy: .public) mock workouts")
        } catch {
            logger.error("Seeding \(profile.rawValue, privacy: .public) failed: \(error, privacy: .public)")
        }
    }
}

#endif

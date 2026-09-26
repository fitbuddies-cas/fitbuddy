import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for the seeding seam the UI tests launch behind (#148).
///
/// It is DEBUG-only test support, and exactly that is the reason to test it:
/// a seam that silently does nothing leaves a UI test failing on an empty
/// screen, one that fires too eagerly would fill a demo run's cache with
/// fixtures nobody asked for.
final class MockDataSeederTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private var container: ModelContainer!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var timestamps: SyncTimestampStore!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.makeInMemory()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        timestamps = SyncTimestampStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        timestamps = nil
        defaults = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Argument parsing

    func testReadsTheProfileAfterTheArgument() {
        XCTAssertEqual(MockDataSeeder.requestedProfile(in: ["-fbSeedMockData", "person-a"]), .personA)
        XCTAssertEqual(MockDataSeeder.requestedProfile(in: ["-fbSeedMockData", "person-b"]), .personB)
        XCTAssertEqual(
            MockDataSeeder.requestedProfile(in: ["-fbSeedMockData", "progression-ready"]),
            .progressionReady
        )
        XCTAssertEqual(MockDataSeeder.requestedProfile(in: ["-fbSeedMockData", "overreached"]), .overreached)
        XCTAssertEqual(MockDataSeeder.requestedProfile(in: ["-fbSeedMockData", "mixed"]), .mixed)
    }

    /// A UI test names a profile by the string in `LaunchArgument.Profile`,
    /// from another process. Every case has to be reachable that way, or a
    /// profile exists that no test can launch (#188).
    func testEveryProfileIsReachableByItsLaunchName() {
        for profile in MockWorkoutProfile.allCases {
            XCTAssertEqual(
                MockDataSeeder.requestedProfile(in: ["-fbSeedMockData", profile.rawValue]),
                profile
            )
        }
    }

    func testNoArgumentMeansNoProfile() {
        XCTAssertNil(MockDataSeeder.requestedProfile(in: []))
        XCTAssertNil(MockDataSeeder.requestedProfile(in: ["-fbResetState"]))
    }

    /// A typo leaves the app on its real cache rather than on a silently
    /// different history.
    func testUnknownOrMissingProfileMeansNoProfile() {
        XCTAssertNil(MockDataSeeder.requestedProfile(in: ["-fbSeedMockData", "person-c"]))
        XCTAssertNil(MockDataSeeder.requestedProfile(in: ["-fbSeedMockData"]))
    }

    // MARK: - Forced reset

    /// The reset has to run on a launch that skips onboarding, which is where
    /// its own hook (`ConsentViewModel.bootstrap()`) never gets reached.
    func testForcedResetRunsWithoutTheOnboardingPath() async throws {
        let keychain = KeychainService()
        try await keychain.save("stale", for: .consentVersion)
        defer { Task { try? await keychain.delete(.consentVersion) } }

        await MockDataSeeder.resetStateIfRequested(
            launchArguments: ["-fbResetState"],
            reset: FirstLaunchResetService(
                defaults: defaults,
                keychain: keychain,
                launchArguments: ["-fbResetState"],
                domainName: suiteName
            )
        )

        let stored = try await keychain.read(.consentVersion)
        XCTAssertNil(stored)
    }

    func testWithoutTheArgumentNothingIsReset() async throws {
        let keychain = KeychainService()
        try await keychain.save("kept", for: .consentVersion)
        defer { Task { try? await keychain.delete(.consentVersion) } }

        await MockDataSeeder.resetStateIfRequested(
            launchArguments: ["-fbSeedMockData", "person-a"],
            reset: FirstLaunchResetService(
                defaults: defaults,
                keychain: keychain,
                launchArguments: [],
                domainName: suiteName
            )
        )

        let stored = try await keychain.read(.consentVersion)
        XCTAssertEqual(stored, "kept")
    }

    // MARK: - Seeding

    func testSeedsTheRequestedWindowAndDatesTheSync() async throws {
        let store = WorkoutStore(modelContainer: container)

        await MockDataSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedMockData", "person-a"],
            timestamps: timestamps,
            now: { self.reference }
        )

        let cached = try await store.workoutCount()
        XCTAssertGreaterThan(cached, 0, "Person A's window must reach the cache")
        let lastSync = await timestamps.lastSync()
        // Without the timestamp the sync strip claims "Never synced" over a
        // full dashboard — a state no real launch produces.
        XCTAssertEqual(lastSync, reference)
    }

    /// The seeded window has to land inside the 90 days the dashboard reads,
    /// or the screens stay empty however many workouts were written.
    func testSeededWorkoutsFallInsideTheDashboardWindow() async throws {
        let store = WorkoutStore(modelContainer: container)

        await MockDataSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedMockData", "person-a"],
            timestamps: timestamps,
            now: { .now }
        )

        let summaries = try await store.workoutSummaries(since: TrainingWindow.start(endingAt: .now))
        XCTAssertGreaterThan(summaries.count, 0)
    }

    /// A profile with several sources reaches the cache as several sources
    /// (#188). Seeding it all under Hevy would label the runs Hevy sessions,
    /// and the second write would delete the first.
    func testAMixedProfileIsCachedUnderEachOfItsSources() async throws {
        let store = WorkoutStore(modelContainer: container)

        await MockDataSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedMockData", "overreached-mixed"],
            timestamps: timestamps,
            now: { self.reference }
        )

        let summaries = try await store.workoutSummaries(since: .distantPast)
        let expected = try MockWorkoutLoader().activities(for: .overreachedMixed).count
        XCTAssertEqual(summaries.count, expected)
        XCTAssertEqual(Set(summaries.map(\.source)), [.hevy, .strava, .polar])
        XCTAssertTrue(
            summaries.contains { $0.cardio?.averageHeartRate != nil },
            "the cardio metrics have to survive the seeding"
        )
    }

    /// Seeding replaces the whole window, not only the sources the new profile
    /// happens to have. Switching the scheme from `mixed` to a Hevy-only
    /// profile without `-fbResetState` used to leave the Strava runs behind,
    /// so the basis line named two sources for a one-source profile.
    func testSeedingAProfileDropsTheSourcesItDoesNotCarry() async throws {
        let store = WorkoutStore(modelContainer: container)

        await MockDataSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedMockData", "mixed"],
            timestamps: timestamps,
            now: { self.reference }
        )
        let seededStrava = try await store.workoutCount(from: .strava)
        XCTAssertGreaterThan(seededStrava, 0, "the mixed profile has to seed Strava first")

        await MockDataSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbSeedMockData", "person-a"],
            timestamps: timestamps,
            now: { self.reference }
        )

        let summaries = try await store.workoutSummaries(since: .distantPast)
        XCTAssertEqual(Set(summaries.map(\.source)), [.hevy])
        let survivingStrava = try await store.workoutCount(from: .strava)
        XCTAssertEqual(survivingStrava, 0)
        XCTAssertEqual(summaries.count, try MockWorkoutLoader().activities(for: .personA).count)
    }

    func testWithoutTheArgumentNothingIsWritten() async throws {
        let store = WorkoutStore(modelContainer: container)

        await MockDataSeeder.seedIfRequested(
            container: container,
            launchArguments: ["-fbResetState"],
            timestamps: timestamps,
            now: { self.reference }
        )

        let cached = try await store.workoutCount()
        XCTAssertEqual(cached, 0)
        let lastSync = await timestamps.lastSync()
        XCTAssertNil(lastSync)
    }
}

import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `SessionResetService` (US-1 AC3 hard logout). Uses the real
/// Keychain on the simulator, an in-memory SwiftData container and an isolated
/// `UserDefaults` suite.
final class SessionResetServiceTests: XCTestCase {
    private var keychain: KeychainService!
    private var container: ModelContainer!
    private var workouts: WorkoutStore!
    private var results: AnalysisResultStore!
    private var timestamps: SyncTimestampStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: SessionResetService!

    override func setUp() async throws {
        try await super.setUp()
        keychain = KeychainService()
        try await clearKeys()
        container = try ModelContainerFactory.makeInMemory()
        workouts = WorkoutStore(modelContainer: container)
        results = AnalysisResultStore(modelContainer: container)
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        timestamps = SyncTimestampStore(defaults: defaults)
        sut = SessionResetService(
            keychain: keychain,
            workouts: workouts,
            results: results,
            timestamps: timestamps
        )
    }

    override func tearDown() async throws {
        try await clearKeys()
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        timestamps = nil
        results = nil
        workouts = nil
        container = nil
        defaults = nil
        keychain = nil
        try await super.tearDown()
    }

    private func clearKeys() async throws {
        for key in KeychainKey.allCases {
            try await keychain.delete(key)
        }
    }

    func testHardLogoutDeletesHevyKey() async throws {
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)

        await sut.hardLogout()

        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(stored)
    }

    func testHardLogoutKeepsClaudeKey() async throws {
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)
        try await keychain.save("sk-ant-abc", for: .claudeAPIKey)

        await sut.hardLogout()

        let stored = try await keychain.read(.claudeAPIKey)
        XCTAssertEqual(stored, "sk-ant-abc")
    }

    func testHardLogoutKeepsConsent() async throws {
        try await keychain.save("v1", for: .consentVersion)

        await sut.hardLogout()

        let stored = try await keychain.read(.consentVersion)
        XCTAssertEqual(stored, "v1")
    }

    func testHardLogoutClearsCachedWorkouts() async throws {
        let activity = ActivityFactory.activity(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000))
        try await workouts.replaceCachedWorkouts(from: .hevy, with: [activity])

        await sut.hardLogout()

        let count = try await workouts.workoutCount()
        XCTAssertEqual(count, 0)
    }

    /// The session is over and the app is back in onboarding: whoever walks
    /// through it next must not find the previous user's Strava history
    /// (US-1 AC3). Unlike the cache teardown for a replaced key (#91).
    func testHardLogoutClearsStravaWorkoutsToo() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await workouts.replaceCachedWorkouts(from: .hevy, with: [ActivityFactory.activity(id: "hevy-1", start: start)])
        try await workouts.replaceCachedWorkouts(from: .strava, with: [
            Activity(id: "strava:1", title: "Run", startTime: start, source: .strava),
        ])

        await sut.hardLogout()

        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertTrue(ids.isEmpty)
    }

    func testHardLogoutDeletesTheStravaCredentials() async throws {
        for key in StravaCredentialStore.ownedKeys {
            try await keychain.save("strava-\(key.rawValue)", for: key)
        }

        await sut.hardLogout()

        for key in StravaCredentialStore.ownedKeys {
            let stored = try await keychain.read(key)
            XCTAssertNil(stored, "\(key.rawValue) must go with the session")
        }
    }

    func testHardLogoutClearsPolarWorkoutsToo() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await workouts.replaceCachedWorkouts(from: .polar, with: [
            Activity(id: "polar:1", title: "Cycling", startTime: start, source: .polar),
        ])

        await sut.hardLogout()

        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertTrue(ids.isEmpty)
    }

    func testHardLogoutDeletesThePolarCredentials() async throws {
        for key in PolarCredentialStore.ownedKeys {
            try await keychain.save("polar-\(key.rawValue)", for: key)
        }

        await sut.hardLogout()

        for key in PolarCredentialStore.ownedKeys {
            let stored = try await keychain.read(key)
            XCTAssertNil(stored, "\(key.rawValue) must go with the session")
        }
    }

    func testHardLogoutClearsSyncTimestamp() async throws {
        await timestamps.setLastSync(Date(timeIntervalSince1970: 1_754_400_000))

        await sut.hardLogout()

        let stored = await timestamps.lastSync()
        XCTAssertNil(stored)
    }

    func testHardLogoutIsIdempotent() async throws {
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)

        await sut.hardLogout()
        await sut.hardLogout()

        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertNil(stored)
    }

    // MARK: - Cache teardown without a logout (#91)

    /// Replacing the Hevy key keeps the session — only the previous key's
    /// training data has to go.
    func testDiscardCachedWorkoutsKeepsTheHevyKey() async throws {
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)

        await sut.discardCachedWorkouts()

        let stored = try await keychain.read(.hevyAPIKey)
        XCTAssertEqual(stored, "hv_live_abc")
    }

    func testDiscardCachedWorkoutsClearsTheCache() async throws {
        let activity = ActivityFactory.activity(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000))
        try await workouts.replaceCachedWorkouts(from: .hevy, with: [activity])

        await sut.discardCachedWorkouts()

        let count = try await workouts.workoutCount()
        XCTAssertEqual(count, 0)
    }

    func testDiscardCachedWorkoutsKeepsStravaWorkouts() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await workouts.replaceCachedWorkouts(from: .hevy, with: [ActivityFactory.activity(id: "hevy-1", start: start)])
        try await workouts.replaceCachedWorkouts(from: .strava, with: [
            Activity(id: "strava:1", title: "Run", startTime: start, source: .strava),
        ])

        await sut.discardCachedWorkouts()

        let ids = try await workouts.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["strava:1"])
    }

    /// The timestamp goes with the cache: a "last synced" line over an empty
    /// dashboard would describe a sync of the previous account.
    func testDiscardCachedWorkoutsClearsTheSyncTimestamp() async {
        await timestamps.setLastSync(Date(timeIntervalSince1970: 1_754_400_000))

        await sut.discardCachedWorkouts()

        let stored = await timestamps.lastSync()
        XCTAssertNil(stored)
    }
}

// MARK: - Stored analysis (#97)

extension SessionResetServiceTests {
    /// A replaced Hevy key drops the cache, and the recommendation written
    /// about that cache has to go with it — otherwise the analysis sheet
    /// restores the previous account's advice over the new account's data.
    func testDiscardingTheCacheAlsoDropsTheStoredAnalysis() async throws {
        try await results.save(
            text: "Add 2.5 kg on bench next session.",
            generatedAt: Date(timeIntervalSince1970: 1_788_000_000),
            context: AnalysisContext(sessionCount: 12, window: .default)
        )

        await sut.discardCachedWorkouts()

        let stored = try await results.latest()
        XCTAssertNil(stored)
    }

    func testHardLogoutDropsTheStoredAnalysis() async throws {
        try await results.save(
            text: "Add 2.5 kg on bench next session.",
            generatedAt: Date(timeIntervalSince1970: 1_788_000_000),
            context: AnalysisContext(sessionCount: 12, window: .default)
        )

        await sut.hardLogout()

        let stored = try await results.latest()
        XCTAssertNil(stored)
    }
}

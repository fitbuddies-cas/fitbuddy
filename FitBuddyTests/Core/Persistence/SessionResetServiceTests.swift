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
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        timestamps = SyncTimestampStore(defaults: defaults)
        sut = SessionResetService(keychain: keychain, workouts: workouts, timestamps: timestamps)
    }

    override func tearDown() async throws {
        try await clearKeys()
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        timestamps = nil
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
        let payload = HevyPayloadFactory.workout(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000))
        let data = try JSONSerialization.data(withJSONObject: payload)
        let dto = try JSONDecoder.hevy.decode(HevyWorkoutDTO.self, from: data)
        try await workouts.replaceCachedWorkouts(with: [dto])

        await sut.hardLogout()

        let count = try await workouts.workoutCount()
        XCTAssertEqual(count, 0)
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
        let payload = HevyPayloadFactory.workout(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000))
        let data = try JSONSerialization.data(withJSONObject: payload)
        let dto = try JSONDecoder.hevy.decode(HevyWorkoutDTO.self, from: data)
        try await workouts.replaceCachedWorkouts(with: [dto])

        await sut.discardCachedWorkouts()

        let count = try await workouts.workoutCount()
        XCTAssertEqual(count, 0)
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

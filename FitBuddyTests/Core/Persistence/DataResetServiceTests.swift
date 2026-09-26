import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `DataResetService` (#83, "Delete all data"). Uses the real
/// Keychain on the simulator, an in-memory SwiftData container and an isolated
/// `UserDefaults` suite.
final class DataResetServiceTests: XCTestCase {
    private var keychain: KeychainService!
    private var container: ModelContainer!
    private var workouts: WorkoutStore!
    private var results: AnalysisResultStore!
    private var timestamps: SyncTimestampStore!
    private var priority: LLMPriorityStore!
    private var skip: LLMKeysSkipStore!
    private var analysisProfile: AnalysisProfileStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: DataResetService!

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
        priority = LLMPriorityStore(defaults: defaults)
        skip = LLMKeysSkipStore(defaults: defaults)
        analysisProfile = AnalysisProfileStore(defaults: defaults)
        sut = DataResetService(
            keychain: keychain,
            workouts: workouts,
            results: results,
            timestamps: timestamps,
            priority: priority,
            skip: skip,
            analysisProfile: analysisProfile,
            defaults: defaults
        )
    }

    override func tearDown() async throws {
        try await clearKeys()
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        skip = nil
        priority = nil
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

    func testDeleteAllDataRemovesEveryKeychainItem() async throws {
        for key in KeychainKey.allCases {
            try await keychain.save("value-for-\(key.rawValue)", for: key)
        }

        await sut.deleteAllData()

        for key in KeychainKey.allCases {
            let stored = try await keychain.read(key)
            XCTAssertNil(stored, "\(key.rawValue) survived the reset")
        }
    }

    /// The consent metadata is part of the wipe on purpose: consent has to be
    /// obtained again after a reset (US-4 AC5).
    func testDeleteAllDataRemovesConsent() async throws {
        try await keychain.save("2026-08-21", for: .consentVersion)
        try await keychain.save("2026-08-21T10:00:00Z", for: .consentTimestamp)

        await sut.deleteAllData()

        let version = try await keychain.read(.consentVersion)
        let timestamp = try await keychain.read(.consentTimestamp)
        XCTAssertNil(version)
        XCTAssertNil(timestamp)
    }

    func testDeleteAllDataClearsCachedWorkouts() async throws {
        let activity = ActivityFactory.activity(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000))
        try await workouts.replaceCachedWorkouts(from: .hevy, with: [activity])

        await sut.deleteAllData()

        let count = try await workouts.workoutCount()
        XCTAssertEqual(count, 0)
    }

    func testDeleteAllDataClearsSyncTimestamp() async throws {
        await timestamps.setLastSync(Date(timeIntervalSince1970: 1_754_400_000))

        await sut.deleteAllData()

        let stored = await timestamps.lastSync()
        XCTAssertNil(stored)
    }

    func testDeleteAllDataClearsPriorityOrder() async throws {
        await priority.save([.mistral, .claude])

        await sut.deleteAllData()

        let stored = await priority.order
        XCTAssertEqual(stored, [])
    }

    func testDeleteAllDataClearsTheSkipMarker() async throws {
        await skip.setSkipped()

        await sut.deleteAllData()

        let isSkipped = await skip.isSkipped
        XCTAssertFalse(isSkipped)
    }

    /// The remembered analysis profile goes with the training it was chosen
    /// for: the next run starts from the default its data suggests (#185).
    func testDeleteAllDataForgetsTheAnalysisProfile() async throws {
        await analysisProfile.save(.overallLoad)

        await sut.deleteAllData()

        let remembered = await analysisProfile.profile
        XCTAssertNil(remembered)
    }

    /// The first-launch marker records the installation, not the session.
    /// Clearing it would only trigger a redundant Keychain purge on the next
    /// launch.
    func testDeleteAllDataKeepsTheFirstLaunchMarker() async throws {
        defaults.set(true, forKey: "fitbuddy.firstLaunchReset.completed")

        await sut.deleteAllData()

        XCTAssertTrue(defaults.bool(forKey: "fitbuddy.firstLaunchReset.completed"))
    }

    func testDeleteAllDataIsIdempotent() async throws {
        try await keychain.save("hv_live_abc", for: .hevyAPIKey)
        await priority.save([.claude])

        await sut.deleteAllData()
        await sut.deleteAllData()

        let stored = try await keychain.read(.hevyAPIKey)
        let order = await priority.order
        XCTAssertNil(stored)
        XCTAssertEqual(order, [])
    }

    /// A failing Keychain must not stop the remaining steps — a reset that
    /// gives up halfway leaves data the user asked to be rid of.
    func testDeleteAllDataClearsTheRestWhenTheKeychainFails() async throws {
        let failing = FailingDeleteKeychainStub()
        let service = DataResetService(
            keychain: failing,
            workouts: workouts,
            results: results,
            timestamps: timestamps,
            priority: priority,
            skip: skip,
            defaults: defaults
        )
        await timestamps.setLastSync(Date(timeIntervalSince1970: 1_754_400_000))
        await priority.save([.claude])
        await skip.setSkipped()

        await service.deleteAllData()

        let lastSync = await timestamps.lastSync()
        let order = await priority.order
        let isSkipped = await skip.isSkipped
        XCTAssertNil(lastSync)
        XCTAssertEqual(order, [])
        XCTAssertFalse(isSkipped)
    }
}

/// `KeychainStoring` whose deletes always fail — the real `KeychainService`
/// cannot be made to fail on demand on the simulator.
private actor FailingDeleteKeychainStub: KeychainStoring {
    func save(_ value: String, for key: KeychainKey) throws {}

    func read(_ key: KeychainKey) throws -> String? { nil }

    func delete(_ key: KeychainKey) throws { throw KeychainError.invalidData }

    func exists(_ key: KeychainKey) throws -> Bool { false }
}

// MARK: - Analysis leftovers (#97, #117)

extension DataResetServiceTests {
    /// The deletion right covers everything the analysis leaves behind, not
    /// just the workouts: the whole history and its leftovers.
    ///
    /// Rows with a stored report (#176) go the same way as prose rows.
    func testDeleteAllDataRemovesTheWholeAnalysisHistory() async throws {
        let reference = Date(timeIntervalSince1970: 1_788_000_000)
        for index in 0..<3 {
            try await results.save(
                text: "Analysis \(index)",
                report: index == 0 ? AnalysisReportFactory.validatedEveryCard : nil,
                provider: .claude,
                generatedAt: reference.addingTimeInterval(Double(index) * 3_600),
                context: AnalysisContext(sessionCount: 12, window: .default)
            )
        }

        await sut.deleteAllData()

        let stored = try await results.recent(limit: 20)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<AnalysisResult>()), 0)
    }

    /// The 60s analysis lock of #117 is gone, but a device that ran a build
    /// with it still holds its timestamp. "Delete all data" removes it too.
    func testDeleteAllDataRemovesTheLegacyAnalysisLockTimestamp() async throws {
        defaults.set(1_788_000_000.0, forKey: "fitbuddy.analysis.lastCallTimestamp")
        XCTAssertEqual(DataResetService.legacyAnalysisLockKey, "fitbuddy.analysis.lastCallTimestamp")

        await sut.deleteAllData()

        XCTAssertNil(defaults.object(forKey: "fitbuddy.analysis.lastCallTimestamp"))
    }
}

import XCTest
@testable import FitBuddy

/// Unit tests for `SyncTimestampStore`, each on an isolated `UserDefaults`
/// suite.
final class SyncTimestampStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: SyncTimestampStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = SyncTimestampStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    func testLastSyncIsNilBeforeFirstSync() async {
        let stored = await sut.lastSync()
        XCTAssertNil(stored)
    }

    func testSetLastSyncRoundTrips() async {
        let date = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.setLastSync(date)

        let stored = await sut.lastSync()
        XCTAssertEqual(stored, date)
    }

    func testEpochTimestampIsDistinctFromNeverSynced() async {
        // `UserDefaults.double(forKey:)` returns 0 for a missing key, so 1970
        // must not be mistaken for "never synced".
        await sut.setLastSync(Date(timeIntervalSince1970: 0))

        let stored = await sut.lastSync()
        XCTAssertEqual(stored, Date(timeIntervalSince1970: 0))
    }

    func testClearRemovesTimestamp() async {
        await sut.setLastSync(Date(timeIntervalSince1970: 1_754_400_000))
        await sut.clear()

        let stored = await sut.lastSync()
        XCTAssertNil(stored)
    }

    func testTimestampSurvivesANewStoreOnTheSameSuite() async throws {
        let date = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.setLastSync(date)

        // A fresh store on the same suite stands in for the next app launch.
        let reopened = SyncTimestampStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let stored = await reopened.lastSync()
        XCTAssertEqual(stored, date)
    }
}

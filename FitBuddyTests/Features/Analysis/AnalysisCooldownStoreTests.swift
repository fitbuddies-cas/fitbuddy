import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisCooldownStore`, each on an isolated `UserDefaults`
/// suite.
final class AnalysisCooldownStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: AnalysisCooldownStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = AnalysisCooldownStore(defaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        sut = nil
        defaults = nil
        try await super.tearDown()
    }

    func testLastCallIsNilBeforeAnyCall() async {
        let stored = await sut.lastCall()
        XCTAssertNil(stored)
    }

    func testRecordCallRoundTrips() async {
        let date = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: date)

        let stored = await sut.lastCall()
        XCTAssertEqual(stored, date)
    }

    func testEpochTimestampIsDistinctFromNeverCalled() async {
        // `UserDefaults.double(forKey:)` returns 0 for a missing key, so 1970
        // must not be mistaken for "never called".
        await sut.recordCall(at: Date(timeIntervalSince1970: 0))

        let stored = await sut.lastCall()
        XCTAssertEqual(stored, Date(timeIntervalSince1970: 0))
    }

    func testClearRemovesTheTimestamp() async {
        await sut.recordCall(at: Date(timeIntervalSince1970: 1_754_400_000))
        await sut.clear()

        let stored = await sut.lastCall()
        XCTAssertNil(stored)
    }

    func testTimestampSurvivesANewStoreOnTheSameSuite() async throws {
        let date = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: date)

        // A fresh store on the same suite stands in for the next app launch.
        let reopened = AnalysisCooldownStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let stored = await reopened.lastCall()
        XCTAssertEqual(stored, date)
    }

    // MARK: - activeCooldown

    func testActiveCooldownIsNilBeforeAnyCall() async {
        let availableAt = await sut.activeCooldown(now: Date(timeIntervalSince1970: 1_754_400_000))
        XCTAssertNil(availableAt)
    }

    func testActiveCooldownReturnsTheEndOfTheWindowWhileStillWithinIt() async {
        let lastCall = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: lastCall)

        let availableAt = await sut.activeCooldown(now: lastCall.addingTimeInterval(1))

        XCTAssertEqual(availableAt, lastCall.addingTimeInterval(AnalysisCooldownStore.duration))
    }

    func testActiveCooldownIsNilOnceTheDurationHasFullyElapsed() async {
        let lastCall = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: lastCall)

        let availableAt = await sut.activeCooldown(now: lastCall.addingTimeInterval(AnalysisCooldownStore.duration + 1))

        XCTAssertNil(availableAt)
    }

    /// Boundary: exactly `duration` elapsed must already count as expired —
    /// the check is `>`, not `>=`, so a caller landing exactly on the edge is
    /// not locked out for an extra instant.
    func testActiveCooldownIsNilAtExactlyTheDurationBoundary() async {
        let lastCall = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: lastCall)

        let availableAt = await sut.activeCooldown(now: lastCall.addingTimeInterval(AnalysisCooldownStore.duration))

        XCTAssertNil(availableAt)
    }
}

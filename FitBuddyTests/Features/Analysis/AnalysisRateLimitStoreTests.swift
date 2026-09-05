import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisRateLimitStore` (#117), each on an isolated
/// `UserDefaults` suite.
final class AnalysisRateLimitStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var sut: AnalysisRateLimitStore!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        sut = AnalysisRateLimitStore(defaults: defaults)
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
        let reopened = AnalysisRateLimitStore(defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        let stored = await reopened.lastCall()
        XCTAssertEqual(stored, date)
    }

    // MARK: - activeLock

    /// The lock is a double-submit guard, not a cost limit — one minute, and
    /// the spending limit in the user's own account does the rest (#117).
    func testTheLockIsOneMinuteLong() {
        XCTAssertEqual(AnalysisRateLimitStore.duration, 60)
    }

    func testActiveLockIsNilBeforeAnyCall() async {
        let availableAt = await sut.activeLock(now: Date(timeIntervalSince1970: 1_754_400_000))
        XCTAssertNil(availableAt)
    }

    func testActiveLockReturnsTheEndOfTheLockWhileStillWithinIt() async {
        let lastCall = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: lastCall)

        let availableAt = await sut.activeLock(now: lastCall.addingTimeInterval(1))

        XCTAssertEqual(availableAt, lastCall.addingTimeInterval(AnalysisRateLimitStore.duration))
    }

    func testActiveLockIsNilOnceTheDurationHasFullyElapsed() async {
        let lastCall = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: lastCall)

        let availableAt = await sut.activeLock(now: lastCall.addingTimeInterval(AnalysisRateLimitStore.duration + 1))

        XCTAssertNil(availableAt)
    }

    /// Boundary: exactly `duration` elapsed must already count as expired —
    /// the check is `>`, not `>=`, so a caller landing exactly on the edge is
    /// not locked out for an extra instant.
    func testActiveLockIsNilAtExactlyTheDurationBoundary() async {
        let lastCall = Date(timeIntervalSince1970: 1_754_400_000)
        await sut.recordCall(at: lastCall)

        let availableAt = await sut.activeLock(now: lastCall.addingTimeInterval(AnalysisRateLimitStore.duration))

        XCTAssertNil(availableAt)
    }
}

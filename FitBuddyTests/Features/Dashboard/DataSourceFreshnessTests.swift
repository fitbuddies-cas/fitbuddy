import XCTest
@testable import FitBuddy

/// Unit tests for `DataSourceFreshness` (US-8 AC1, #40): the 24 h judgement the
/// dashboard's stale indicator hangs on.
final class DataSourceFreshnessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testNoSyncAtAllIsNever() {
        XCTAssertEqual(DataSourceFreshness(lastSync: nil, now: now), .never)
    }

    func testRecentSyncIsFresh() {
        let lastSync = now.addingTimeInterval(-3_600)
        XCTAssertEqual(DataSourceFreshness(lastSync: lastSync, now: now), .fresh)
    }

    /// The AC says "longer than 24 h", so the boundary itself is still fresh —
    /// a sync exactly a day old has not yet crossed anything.
    func testExactlyTwentyFourHoursIsStillFresh() {
        let lastSync = now.addingTimeInterval(-DataSourceFreshness.staleThreshold)
        XCTAssertEqual(DataSourceFreshness(lastSync: lastSync, now: now), .fresh)
    }

    func testJustPastTwentyFourHoursIsStale() {
        let lastSync = now.addingTimeInterval(-DataSourceFreshness.staleThreshold - 1)
        XCTAssertEqual(DataSourceFreshness(lastSync: lastSync, now: now), .stale(since: lastSync))
    }

    func testStaleCarriesTheTimestampItWentStaleFrom() {
        let lastSync = now.addingTimeInterval(-5 * 86_400)
        guard case .stale(let since) = DataSourceFreshness(lastSync: lastSync, now: now) else {
            return XCTFail("Expected .stale for a five-day-old sync")
        }
        XCTAssertEqual(since, lastSync)
    }

    /// A clock change or a restored backup can put the last sync ahead of now.
    /// Flagging that as stale would show a warning on data the device itself
    /// believes is newer than the present.
    func testFutureTimestampIsNotStale() {
        XCTAssertEqual(DataSourceFreshness(lastSync: now.addingTimeInterval(600), now: now), .fresh)
    }

    func testOnlyFreshNeedsNoAttention() {
        XCTAssertFalse(DataSourceFreshness.fresh.needsAttention)
        XCTAssertTrue(DataSourceFreshness.never.needsAttention)
        XCTAssertTrue(DataSourceFreshness.stale(since: now).needsAttention)
    }
}

import XCTest
@testable import FitBuddy

/// Unit tests for `DataSourceStatus` (US-8, #40): what one row of the
/// dashboard's status strip says about its source.
final class DataSourceStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testFreshnessFollowsTheLastSync() {
        let stale = DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-2 * 86_400))
        let fresh = DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-60))

        XCTAssertEqual(stale.freshness(now: now), .stale)
        XCTAssertEqual(fresh.freshness(now: now), .fresh)
    }

    func testStaleSourceNeedsAttention() {
        let sut = DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-3 * 86_400))
        XCTAssertTrue(sut.needsAttention(now: now))
    }

    func testNeverSyncedSourceNeedsAttention() {
        XCTAssertTrue(DataSourceStatus(source: .hevy, lastSync: nil).needsAttention(now: now))
    }

    func testFreshSourceNeedsNoAttention() {
        let sut = DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-300))
        XCTAssertFalse(sut.needsAttention(now: now))
    }

    /// A running sync is already the answer a retry button would ask for, so
    /// the stale treatment stands down until it reports back.
    func testSyncingSourceNeedsNoAttentionEvenWhenStale() {
        let sut = DataSourceStatus(
            source: .hevy,
            lastSync: now.addingTimeInterval(-4 * 86_400),
            isSyncing: true
        )

        XCTAssertFalse(sut.needsAttention(now: now))
        XCTAssertEqual(sut.freshness(now: now), .stale)
    }

    func testSummaryReportsTheAgeOfTheLastSync() {
        let sut = DataSourceStatus(source: .hevy, lastSync: now.addingTimeInterval(-2 * 86_400))
        XCTAssertEqual(sut.summary(now: now), "Last synced 2 days ago")
    }

    func testSummaryOfANeverSyncedSource() {
        XCTAssertEqual(DataSourceStatus(source: .hevy, lastSync: nil).summary(now: now), "Never synced")
    }

    func testSyncingSourceSaysSoInsteadOfPrintingAnAge() {
        let sut = DataSourceStatus(source: .hevy, lastSync: nil, isSyncing: true)
        XCTAssertEqual(sut.summary(now: now), "Syncing…")
    }

    /// The strip renders the sources in a `ForEach`, which needs the identity
    /// to be the source itself — two rows for one provider would be a bug.
    func testIdentityIsTheSource() {
        XCTAssertEqual(DataSourceStatus(source: .strava, lastSync: nil).id, .strava)
    }
}

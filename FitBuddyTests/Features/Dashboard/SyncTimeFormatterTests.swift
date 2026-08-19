import XCTest
@testable import FitBuddy

/// Unit tests for `SyncTimeFormatter` (issue #28): the "last synced" line the
/// dashboard must always show (US-2 AC2).
final class SyncTimeFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)

    func testSecondsReadAsJustNow() {
        XCTAssertEqual(relative(secondsAgo: 0), "just now")
        XCTAssertEqual(relative(secondsAgo: 59), "just now")
    }

    func testMinutesAreRoundedDown() {
        XCTAssertEqual(relative(secondsAgo: 60), "1 min ago")
        XCTAssertEqual(relative(secondsAgo: 119), "1 min ago")
        XCTAssertEqual(relative(secondsAgo: 3_540), "59 min ago")
    }

    /// The reason this is not `RelativeDateTimeFormatter`: an hours-old sync
    /// keeps its minutes.
    func testHoursKeepTheirMinutes() {
        XCTAssertEqual(relative(secondsAgo: 8_040), "2 h 14 min ago")
        XCTAssertEqual(relative(secondsAgo: 3_600), "1 h ago")
        XCTAssertEqual(relative(secondsAgo: 86_399), "23 h 59 min ago")
    }

    func testDaysAreSingularAtOne() {
        XCTAssertEqual(relative(secondsAgo: 86_400), "1 day ago")
        XCTAssertEqual(relative(secondsAgo: 3 * 86_400), "3 days ago")
    }

    /// A restored backup or a clock change must not produce "in 4 hours".
    func testFutureTimestampReadsAsJustNow() {
        XCTAssertEqual(relative(secondsAgo: -14_400), "just now")
    }

    func testLastSyncedComposesTheFullLine() {
        XCTAssertEqual(
            SyncTimeFormatter.lastSynced(now.addingTimeInterval(-900), now: now),
            "Last synced 15 min ago"
        )
    }

    func testLastSyncedWithoutATimestampSaysNever() {
        XCTAssertEqual(SyncTimeFormatter.lastSynced(nil, now: now), "Never synced")
    }

    private func relative(secondsAgo: TimeInterval) -> String {
        SyncTimeFormatter.relative(since: now.addingTimeInterval(-secondsAgo), now: now)
    }
}

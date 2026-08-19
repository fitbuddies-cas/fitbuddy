import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisWindow` (issue #30): the two 4-week windows the
/// prompt reasons over.
final class AnalysisWindowTests: XCTestCase {
    private var calendar: Calendar!
    /// 2025-06-15 12:26:40 UTC.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    }

    /// The reference day counts itself, so the window spans exactly 28 days —
    /// the off-by-one that would otherwise deflate every per-week average.
    func testRecentWindowSpansExactly28Days() {
        let start = AnalysisWindow.start(endingAt: reference, calendar: calendar)
        let end = calendar.startOfDay(for: reference)
        let days = calendar.dateComponents([.day], from: start, to: end).day

        XCTAssertEqual(days, 27)
        XCTAssertEqual(start, calendar.startOfDay(for: start))
    }

    func testPreviousWindowEndsWhereTheRecentOneBegins() {
        let recentStart = AnalysisWindow.start(endingAt: reference, calendar: calendar)
        let previousStart = AnalysisWindow.previousStart(endingAt: reference, calendar: calendar)
        let days = calendar.dateComponents([.day], from: previousStart, to: recentStart).day

        XCTAssertEqual(days, AnalysisWindow.days)
    }

    func testWeekZeroIsTheSevenDaysEndingOnTheReferenceDay() {
        let start = AnalysisWindow.weekStart(0, endingAt: reference, calendar: calendar)
        let midnight = calendar.startOfDay(for: reference)

        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: midnight).day, 6)
    }

    /// The four weeks have to tile the window exactly: week 3 must start on
    /// the window's first day, or a session would fall through the buckets.
    func testWeeksTileTheWindowWithoutGaps() {
        let windowStart = AnalysisWindow.start(endingAt: reference, calendar: calendar)
        let lastWeekStart = AnalysisWindow.weekStart(3, endingAt: reference, calendar: calendar)

        XCTAssertEqual(lastWeekStart, windowStart)
    }

    func testWindowStartIsIndependentOfTheTimeOfDay() {
        let morning = reference.addingTimeInterval(-40_000)
        XCTAssertEqual(
            AnalysisWindow.start(endingAt: reference, calendar: calendar),
            AnalysisWindow.start(endingAt: morning, calendar: calendar)
        )
    }
}

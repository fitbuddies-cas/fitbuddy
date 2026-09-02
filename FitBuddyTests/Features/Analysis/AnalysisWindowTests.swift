import XCTest
@testable import FitBuddy

/// Unit tests for `AnalysisWindow` (issues #30 and #87): the two equally long
/// windows the prompt reasons over, and the fallback ladder that widens them
/// when the last four weeks are empty.
final class AnalysisWindowTests: XCTestCase {
    private var calendar: Calendar!
    /// 2025-06-15 12:26:40 UTC.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    }

    // MARK: - Window geometry

    /// The reference day counts itself, so the window spans exactly 28 days —
    /// the off-by-one that would otherwise deflate every per-week average.
    func testRecentWindowSpansExactly28Days() {
        let start = AnalysisWindow.default.start(endingAt: reference, calendar: calendar)
        let end = calendar.startOfDay(for: reference)
        let days = calendar.dateComponents([.day], from: start, to: end).day

        XCTAssertEqual(days, 27)
        XCTAssertEqual(start, calendar.startOfDay(for: start))
    }

    func testPreviousWindowEndsWhereTheRecentOneBegins() {
        for window in AnalysisWindow.ladder {
            let recentStart = window.start(endingAt: reference, calendar: calendar)
            let previousStart = window.previousStart(endingAt: reference, calendar: calendar)
            let days = calendar.dateComponents([.day], from: previousStart, to: recentStart).day

            XCTAssertEqual(days, window.days, "\(window.weeks) weeks")
        }
    }

    func testWeekZeroIsTheSevenDaysEndingOnTheReferenceDay() {
        let start = AnalysisWindow.weekStart(0, endingAt: reference, calendar: calendar)
        let midnight = calendar.startOfDay(for: reference)

        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: midnight).day, 6)
    }

    /// The weeks have to tile every rung exactly: the last week must start on
    /// the window's first day, or a session would fall through the buckets.
    func testWeeksTileEveryWindowWithoutGaps() {
        for window in AnalysisWindow.ladder {
            let windowStart = window.start(endingAt: reference, calendar: calendar)
            let lastWeekStart = AnalysisWindow.weekStart(
                window.weeks - 1,
                endingAt: reference,
                calendar: calendar
            )

            XCTAssertEqual(lastWeekStart, windowStart, "\(window.weeks) weeks")
        }
    }

    func testWindowStartIsIndependentOfTheTimeOfDay() {
        let morning = reference.addingTimeInterval(-40_000)
        XCTAssertEqual(
            AnalysisWindow.default.start(endingAt: reference, calendar: calendar),
            AnalysisWindow.default.start(endingAt: morning, calendar: calendar)
        )
    }

    // MARK: - Fallback ladder (#87)

    func testLadderIs4Then8Then13Weeks() {
        XCTAssertEqual(AnalysisWindow.ladder.map(\.weeks), [4, 8, 13])
        XCTAssertEqual(AnalysisWindow.default.weeks, 4)
        XCTAssertEqual(AnalysisWindow.widest.weeks, 13)
    }

    /// The widest rung and the dashboard's cache window have to be the same
    /// span, or the analysis button could appear for data no window reaches —
    /// the dead end #87 exists to close.
    func testWidestWindowMatchesTheCachedTrainingWindow() {
        XCTAssertEqual(AnalysisWindow.widest.days, TrainingWindow.spanDays)
        XCTAssertEqual(
            AnalysisWindow.widest.start(endingAt: reference, calendar: calendar),
            TrainingWindow.start(endingAt: reference, calendar: calendar)
        )
    }

    func testResolvePicksTheDefaultWhenTheLastFourWeeksHoldTraining() {
        let window = AnalysisWindow.resolve(
            for: [workout(daysAgo: 3), workout(daysAgo: 40)],
            endingAt: reference,
            calendar: calendar
        )

        XCTAssertEqual(window, .default)
    }

    func testResolveWidensToEightWeeksWhenOnlyTheOlderHalfHoldsTraining() {
        let window = AnalysisWindow.resolve(
            for: [workout(daysAgo: 40)],
            endingAt: reference,
            calendar: calendar
        )

        XCTAssertEqual(window?.weeks, 8)
    }

    func testResolveWidensTo13WeeksWhenTrainingSatMoreThanEightWeeksBack() {
        let window = AnalysisWindow.resolve(
            for: [workout(daysAgo: 80)],
            endingAt: reference,
            calendar: calendar
        )

        XCTAssertEqual(window?.weeks, 13)
    }

    /// The first rung with training wins, even when a wider one would hold
    /// more sessions — the recent window is the one the recommendation is for.
    func testResolveStopsAtTheNarrowestRungThatHoldsTraining() {
        let window = AnalysisWindow.resolve(
            for: [workout(daysAgo: 2), workout(daysAgo: 40), workout(daysAgo: 80)],
            endingAt: reference,
            calendar: calendar
        )

        XCTAssertEqual(window, .default)
    }

    func testResolveReturnsNilWhenNoWindowHoldsTraining() {
        XCTAssertNil(AnalysisWindow.resolve(for: [], endingAt: reference, calendar: calendar))
        XCTAssertNil(
            AnalysisWindow.resolve(
                for: [workout(daysAgo: 200)],
                endingAt: reference,
                calendar: calendar
            )
        )
    }

    /// A session on the very first day of a rung belongs to it — the boundary
    /// is inclusive, or a workout could fall between two rungs.
    func testResolveIncludesAWorkoutOnTheWindowsFirstDay() {
        let start = AnalysisWindow.default.start(endingAt: reference, calendar: calendar)
        let window = AnalysisWindow.resolve(
            for: [workout(at: start)],
            endingAt: reference,
            calendar: calendar
        )

        XCTAssertEqual(window, .default)
    }

    // MARK: - Helpers

    private func workout(daysAgo: Int) -> WorkoutSummary {
        workout(at: reference.addingTimeInterval(-Double(daysAgo) * 86_400))
    }

    private func workout(at startTime: Date) -> WorkoutSummary {
        WorkoutSummary(
            id: "w-\(startTime.timeIntervalSince1970)",
            title: "Push Day",
            startTime: startTime,
            volumeKg: 3_000,
            exerciseCount: 4,
            countedSetCount: 12
        )
    }
}

import XCTest
@testable import FitBuddy

/// Unit tests for `WorkoutDurationFormatter` (#98, extended for #181).
final class WorkoutDurationFormatterTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_750_000_000)

    func testMinutesOnlyBelowAnHour() {
        XCTAssertEqual(session(after: 52 * 60), "52 min")
    }

    func testHoursAndMinutes() {
        XCTAssertEqual(session(after: 72 * 60), "1 h 12 min")
    }

    /// A round hour drops the "0 min" — it says nothing.
    func testARoundHourOmitsTheMinutes() {
        XCTAssertEqual(session(after: 2 * 3_600), "2 h")
    }

    /// Seconds are rounded down, so a session is never reported as longer than
    /// it was.
    func testSecondsAreTruncatedRatherThanRounded() {
        XCTAssertEqual(session(after: 52 * 60 + 59), "52 min")
    }

    /// Shorter than the unit but still a session — "0 min" would read as one
    /// that never happened.
    func testASubMinuteSessionIsNamedAsSuch() {
        XCTAssertEqual(session(after: 40), "< 1 min")
    }

    /// Hevy never closed the session, so there is no duration to show.
    func testNoEndTimeMeansNoDuration() {
        XCTAssertNil(WorkoutDurationFormatter.session(from: Self.start, to: nil))
    }

    /// A clock change or a corrupted row: an end before the start is not a
    /// negative duration, it is an unknown one.
    func testAnEndBeforeTheStartMeansNoDuration() {
        XCTAssertNil(session(after: -600))
        XCTAssertNil(session(after: 0))
    }

    // MARK: - Durations in seconds (#181)

    /// What a connector delivers for an endurance activity is a moving time,
    /// not a pair of dates.
    func testASecondsDurationReadsLikeASession() {
        XCTAssertEqual(WorkoutDurationFormatter.seconds(3_120), "52 min")
        XCTAssertEqual(WorkoutDurationFormatter.seconds(6_120), "1 h 42 min")
        XCTAssertEqual(WorkoutDurationFormatter.seconds(7_200), "2 h")
        XCTAssertEqual(WorkoutDurationFormatter.seconds(30), "< 1 min")
    }

    /// A weekly endurance total stays in hours rather than rolling into days.
    func testAWeeklyTotalStaysInHours() {
        XCTAssertEqual(WorkoutDurationFormatter.seconds(11 * 3_600), "11 h")
        XCTAssertEqual(WorkoutDurationFormatter.seconds(26 * 3_600 + 30 * 60), "26 h 30 min")
    }

    func testAZeroOrNegativeDurationIsNoDuration() {
        XCTAssertNil(WorkoutDurationFormatter.seconds(0))
        XCTAssertNil(WorkoutDurationFormatter.seconds(-60))
    }

    private func session(after seconds: TimeInterval) -> String? {
        WorkoutDurationFormatter.session(
            from: Self.start,
            to: Self.start.addingTimeInterval(seconds)
        )
    }
}

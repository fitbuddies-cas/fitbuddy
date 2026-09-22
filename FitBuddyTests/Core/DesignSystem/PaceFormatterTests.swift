import XCTest
@testable import FitBuddy

/// Unit tests for `PaceFormatter` (#181).
final class PaceFormatterTests: XCTestCase {
    func testASpeedBecomesMinutesPerKilometre() {
        XCTAssertEqual(PaceFormatter.perKilometer(metersPerSecond: 4), "4:10 /km")
        XCTAssertEqual(PaceFormatter.perKilometer(metersPerSecond: 2.5), "6:40 /km")
        XCTAssertEqual(PaceFormatter.perKilometer(metersPerSecond: 1_000 / 312), "5:12 /km")
    }

    /// The seconds are padded, so a pace column lines up under tabular
    /// numerals.
    func testSecondsArePaddedToTwoDigits() {
        XCTAssertEqual(PaceFormatter.perKilometer(metersPerSecond: 1_000 / 305), "5:05 /km")
        XCTAssertEqual(PaceFormatter.perKilometer(metersPerSecond: 1_000 / 300), "5:00 /km")
    }

    /// A session with no usable speed shows no pace — `"0:00 /km"` would be a
    /// wrong figure rather than a missing one.
    func testAZeroOrNegativeSpeedHasNoPace() {
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: 0))
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: -3))
    }

    func testANonFiniteSpeedHasNoPace() {
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: .nan))
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: .infinity))
    }

    /// A watch drifting on a bench yields hours per kilometre — a number, but
    /// not one anybody ran.
    func testAnImplausiblySlowPaceIsDropped() {
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: 0.1))
        // A slow hike is still a pace.
        XCTAssertEqual(PaceFormatter.perKilometer(metersPerSecond: 0.5), "33:20 /km")
    }

    /// The cap itself: the last pace still printed, and the first one dropped.
    func testTheCapHoldsAtItsBoundary() {
        XCTAssertEqual(PaceFormatter.perKilometer(metersPerSecond: 1_000 / 5_999), "99:59 /km")
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: 1_000 / 6_000))
    }

    /// A speed this small is positive and finite, and its pace does not fit in
    /// an `Int` — the bound has to hold while the pace is still a `Double`, or
    /// the formatter traps instead of returning `nil`.
    func testAVanishinglySmallSpeedDoesNotTrap() {
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: 1e-20))
        XCTAssertNil(PaceFormatter.plain(metersPerSecond: 1e-20))
        XCTAssertNil(PaceFormatter.perKilometer(metersPerSecond: .leastNonzeroMagnitude))
    }

    /// The prompt has no column header, so the unit is spelled out.
    func testThePlainFormNamesTheUnit() {
        XCTAssertEqual(PaceFormatter.plain(metersPerSecond: 2.5), "6:40 min/km")
        XCTAssertNil(PaceFormatter.plain(metersPerSecond: 0))
    }

    /// A pace the caller already holds in minutes per kilometre — what a
    /// model states on a metric card (#186) — enters the same clock rule.
    func testAPaceGivenInMinutesPerKilometre() {
        XCTAssertEqual(PaceFormatter.perKilometer(minutesPerKilometer: 5 + 20.0 / 60), "5:20 /km")
        XCTAssertEqual(PaceFormatter.perKilometer(minutesPerKilometer: 6), "6:00 /km")
        XCTAssertEqual(PaceFormatter.plain(minutesPerKilometer: 5.5), "5:30 min/km")
    }

    /// The same bounds as the speed form: nothing at or below zero, nothing
    /// that is not a number, nothing slower than 99:59.
    func testAnImpossiblePaceInMinutesPerKilometreIsNil() {
        XCTAssertNil(PaceFormatter.perKilometer(minutesPerKilometer: 0))
        XCTAssertNil(PaceFormatter.perKilometer(minutesPerKilometer: -5))
        XCTAssertNil(PaceFormatter.perKilometer(minutesPerKilometer: .nan))
        XCTAssertNil(PaceFormatter.perKilometer(minutesPerKilometer: .infinity))
        XCTAssertEqual(PaceFormatter.perKilometer(minutesPerKilometer: 99 + 59.0 / 60), "99:59 /km")
        XCTAssertNil(PaceFormatter.perKilometer(minutesPerKilometer: 100))
    }

    /// Both entry points describe the same pace with the same digits.
    func testTheSpeedAndTheMinuteFormAgree() {
        XCTAssertEqual(
            PaceFormatter.perKilometer(metersPerSecond: 1_000 / 320),
            PaceFormatter.perKilometer(minutesPerKilometer: 320 / 60)
        )
    }
}

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

    /// The prompt has no column header, so the unit is spelled out.
    func testThePlainFormNamesTheUnit() {
        XCTAssertEqual(PaceFormatter.plain(metersPerSecond: 2.5), "6:40 min/km")
        XCTAssertNil(PaceFormatter.plain(metersPerSecond: 0))
    }
}

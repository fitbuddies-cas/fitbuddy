import XCTest
@testable import FitBuddy

/// Unit tests for `HeartRateFormatter` (#181).
final class HeartRateFormatterTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    func testAHeartRateIsWholeBeatsPerMinute() {
        XCTAssertEqual(HeartRateFormatter.display(148, locale: english), "148 bpm")
        XCTAssertEqual(HeartRateFormatter.display(148.4, locale: english), "148 bpm")
    }

    /// Half away from zero, the rule the analysis figures already round by.
    func testAHalfBeatRoundsUp() {
        XCTAssertEqual(HeartRateFormatter.display(148.5, locale: english), "149 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(148.5), "149 bpm")
    }

    func testZeroAndNegativeValuesReadAsZero() {
        XCTAssertEqual(HeartRateFormatter.display(0, locale: english), "0 bpm")
        XCTAssertEqual(HeartRateFormatter.display(-4, locale: english), "0 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(-4), "0 bpm")
    }

    /// A value just below zero rounds to negative zero, which is not smaller
    /// than zero and would print as `"-0 bpm"` if the guard tested the rounded
    /// figure instead of the input.
    func testAValueRoundingToNegativeZeroReadsAsZero() {
        XCTAssertEqual(HeartRateFormatter.display(-0.2, locale: english), "0 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(-0.4), "0 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(-0.0), "0 bpm")
    }

    /// A heart rate stays inside three digits, so no European locale moves a
    /// digit — `ar_EG` writes its own numerals and fails the moment the
    /// injected locale stops reaching the formatter.
    func testTheDisplayFormFollowsTheInjectedLocale() {
        XCTAssertEqual(HeartRateFormatter.display(148, locale: german), "148 bpm")
        XCTAssertEqual(
            HeartRateFormatter.display(148, locale: Locale(identifier: "ar_EG")),
            "\u{661}\u{664}\u{668} bpm"
        )
    }

    /// A corrupted row can hold a value that is not a number; neither form
    /// prints `"∞ bpm"` or `"inf bpm"`.
    func testANonFiniteHeartRateReadsAsZero() {
        XCTAssertEqual(HeartRateFormatter.display(.infinity, locale: english), "0 bpm")
        XCTAssertEqual(HeartRateFormatter.display(.nan, locale: english), "0 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(.infinity), "0 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(.nan), "0 bpm")
    }

    func testThePlainFormIsLocaleFree() {
        XCTAssertEqual(HeartRateFormatter.plain(148), "148 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(62.4), "62 bpm")
    }

    /// The figure and its unit separately, for the one layout that sets them
    /// in different type — the recovery card's four-column row (#184, #186).
    func testTheValueAndTheUnitCanBeReadApart() {
        XCTAssertEqual(HeartRateFormatter.value(148.4, locale: english), "148")
        XCTAssertEqual(HeartRateFormatter.unit, "bpm")
        XCTAssertEqual(
            HeartRateFormatter.value(148.4, locale: english) + " " + HeartRateFormatter.unit,
            HeartRateFormatter.display(148.4, locale: english)
        )
    }
}

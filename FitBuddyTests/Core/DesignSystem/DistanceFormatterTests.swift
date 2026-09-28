import XCTest
@testable import FitBuddy

/// Unit tests for `DistanceFormatter` (#181).
final class DistanceFormatterTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    // MARK: - Display

    func testBelowAKilometreStaysInMetres() {
        XCTAssertEqual(DistanceFormatter.display(850, locale: english), "850 m")
        XCTAssertEqual(DistanceFormatter.display(1, locale: english), "1 m")
    }

    func testAKilometreAndUpIsReadToATenth() {
        XCTAssertEqual(DistanceFormatter.display(1_000, locale: english), "1 km")
        XCTAssertEqual(DistanceFormatter.display(8_400, locale: english), "8.4 km")
        XCTAssertEqual(DistanceFormatter.display(42_195, locale: english), "42.2 km")
    }

    /// Past 100 km — a training week rather than a session — the tenth is
    /// noise next to three digits.
    func testAboveAHundredKilometresDropsTheDecimal() {
        XCTAssertEqual(DistanceFormatter.display(104_300, locale: english), "104 km")
        XCTAssertEqual(DistanceFormatter.display(99_960, locale: english), "100 km")
    }

    /// The threshold is tested on rounded metres, so the metre form never
    /// prints a figure that already reads as a kilometre.
    func testJustUnderAKilometreRoundsIntoKilometres() {
        XCTAssertEqual(DistanceFormatter.display(999, locale: english), "999 m")
        XCTAssertEqual(DistanceFormatter.display(999.6, locale: english), "1 km")
    }

    /// A corrupted row is not a distance; the caller decides whether to show
    /// the cell at all.
    func testZeroAndNegativeValuesReadAsZeroMetres() {
        XCTAssertEqual(DistanceFormatter.display(0, locale: english), "0 m")
        XCTAssertEqual(DistanceFormatter.display(-5, locale: english), "0 m")
    }

    /// A value just below zero rounds to negative zero, which is not smaller
    /// than zero — `"-0 m"` would leak through a guard that tested the rounded
    /// figure instead of the input.
    func testAValueRoundingToNegativeZeroReadsAsZeroMetres() {
        XCTAssertEqual(DistanceFormatter.display(-0.2, locale: english), "0 m")
        XCTAssertEqual(DistanceFormatter.plain(-0.4), "0 m")
    }

    /// Past 100 km the value is rounded once, at the precision it is printed
    /// with — otherwise Foundation's half-even rule and
    /// `PlainNumberFormatter`'s half-away-from-zero disagree about `100.5`.
    func testDisplayAndPlainAgreePastAHundredKilometres() {
        for meters in [100_450.0, 102_500, 104_500] {
            XCTAssertEqual(
                DistanceFormatter.display(meters, locale: english),
                DistanceFormatter.plain(meters),
                "display and plain disagree at \(meters) m"
            )
        }
        XCTAssertEqual(DistanceFormatter.display(100_450, locale: english), "100 km")
        XCTAssertEqual(DistanceFormatter.display(102_500, locale: english), "103 km")
        XCTAssertEqual(DistanceFormatter.display(104_500, locale: english), "105 km")
    }

    /// Past 100 km the whole-kilometre figure is rounded from the distance
    /// itself, never from a copy already rounded to a tenth (#186).
    ///
    /// `123.456 km` rounded to a tenth is `123.5`, and rounding *that* half
    /// away from zero reports `"124 km"` — half a kilometre the person never
    /// covered. The tenth decides only which range the distance falls in.
    func testAWholeKilometreFigureIsNotRoundedTwice() {
        XCTAssertEqual(DistanceFormatter.display(123_456, locale: english), "123 km")
        XCTAssertEqual(DistanceFormatter.plain(123_456), "123 km")
        XCTAssertEqual(DistanceFormatter.plain(100_450), "100 km")
    }

    /// A tenth that carries no digit is not printed, in either form: the
    /// metric card reads `"32 km → 35 km"`, not `"32.0 km → 35.0 km"` (#186).
    func testATrailingZeroIsDroppedInBothForms() {
        XCTAssertEqual(DistanceFormatter.display(32_000, locale: english), "32 km")
        XCTAssertEqual(DistanceFormatter.display(32_000, locale: german), "32 km")
        XCTAssertEqual(DistanceFormatter.plain(32_000), "32 km")
        XCTAssertEqual(DistanceFormatter.display(8_400, locale: english), "8.4 km")
    }

    /// A corrupted row can hold a value that is not a number; neither form
    /// prints `"∞ km"` or `"inf km"`.
    func testANonFiniteDistanceReadsAsZeroMetres() {
        XCTAssertEqual(DistanceFormatter.display(.infinity, locale: english), "0 m")
        XCTAssertEqual(DistanceFormatter.display(.nan, locale: english), "0 m")
        XCTAssertEqual(DistanceFormatter.plain(.infinity), "0 m")
        XCTAssertEqual(DistanceFormatter.plain(.nan), "0 m")
    }

    func testGroupingFollowsTheLocale() {
        XCTAssertEqual(DistanceFormatter.display(1_240_000, locale: english), "1,240 km")
        XCTAssertEqual(DistanceFormatter.display(8_400, locale: german), "8,4 km")
        XCTAssertEqual(DistanceFormatter.display(850, locale: german), "850 m")
    }

    // MARK: - Plain

    /// The prompt's form is the same on every device — a decimal period, no
    /// grouping separator.
    func testThePlainFormIsLocaleFree() {
        XCTAssertEqual(DistanceFormatter.plain(8_400), "8.4 km")
        XCTAssertEqual(DistanceFormatter.plain(850), "850 m")
        XCTAssertEqual(DistanceFormatter.plain(1_240_000), "1240 km")
    }

    /// A trailing zero says nothing to a model.
    func testThePlainFormDropsTrailingZeros() {
        XCTAssertEqual(DistanceFormatter.plain(5_000), "5 km")
    }

    func testThePlainFormUsesTheSameRanges() {
        XCTAssertEqual(DistanceFormatter.plain(104_300), "104 km")
        XCTAssertEqual(DistanceFormatter.plain(999.6), "1 km")
        XCTAssertEqual(DistanceFormatter.plain(0), "0 m")
    }
}

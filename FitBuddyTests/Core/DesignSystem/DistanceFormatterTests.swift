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
        XCTAssertEqual(DistanceFormatter.display(1_000, locale: english), "1.0 km")
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
        XCTAssertEqual(DistanceFormatter.display(999.6, locale: english), "1.0 km")
    }

    /// A corrupted row is not a distance; the caller decides whether to show
    /// the cell at all.
    func testZeroAndNegativeValuesReadAsZeroMetres() {
        XCTAssertEqual(DistanceFormatter.display(0, locale: english), "0 m")
        XCTAssertEqual(DistanceFormatter.display(-5, locale: english), "0 m")
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

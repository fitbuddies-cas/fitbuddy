import XCTest
@testable import FitBuddy

/// Unit tests for `ElevationFormatter` (#181).
final class ElevationFormatterTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    func testAscentIsWholeMetres() {
        XCTAssertEqual(ElevationFormatter.display(340, locale: english), "340 m")
        XCTAssertEqual(ElevationFormatter.display(340.4, locale: english), "340 m")
        XCTAssertEqual(ElevationFormatter.display(340.5, locale: english), "341 m")
    }

    /// A climb never becomes kilometres — `"1.2 km"` of ascent is a figure no
    /// training log prints.
    func testAThousandMetresStaysInMetres() {
        XCTAssertEqual(ElevationFormatter.display(1_200, locale: english), "1,200 m")
        XCTAssertEqual(ElevationFormatter.display(1_200, locale: german), "1.200 m")
    }

    func testZeroNegativeAndNonFiniteValuesReadAsZero() {
        XCTAssertEqual(ElevationFormatter.display(0, locale: english), "0 m")
        XCTAssertEqual(ElevationFormatter.display(-120, locale: english), "0 m")
        XCTAssertEqual(ElevationFormatter.display(.infinity, locale: english), "0 m")
        XCTAssertEqual(ElevationFormatter.display(.nan, locale: english), "0 m")
        XCTAssertEqual(ElevationFormatter.plain(.infinity), "0 m")
    }

    /// A value just below zero rounds to negative zero, which is not smaller
    /// than zero — `"-0 m"` would leak through a guard that tested the rounded
    /// figure instead of the input.
    func testAValueRoundingToNegativeZeroReadsAsZero() {
        XCTAssertEqual(ElevationFormatter.display(-0.2, locale: english), "0 m")
        XCTAssertEqual(ElevationFormatter.plain(-0.4), "0 m")
    }

    /// The prompt's form carries no grouping separator, so the model reads one
    /// number rather than two.
    func testThePlainFormIsLocaleFree() {
        XCTAssertEqual(ElevationFormatter.plain(1_200), "1200 m")
        XCTAssertEqual(ElevationFormatter.plain(340.5), "341 m")
    }

    /// Both forms round by the same rule, so a card and the prompt behind it
    /// cannot state a different climb.
    func testDisplayAndPlainAgreeOnTheFigure() {
        for meters in [340.5, 1_200.5, 2_499.5] {
            XCTAssertEqual(
                ElevationFormatter.display(meters, locale: english).replacingOccurrences(
                    of: ",",
                    with: ""
                ),
                ElevationFormatter.plain(meters),
                "display and plain disagree at \(meters) m"
            )
        }
    }
}

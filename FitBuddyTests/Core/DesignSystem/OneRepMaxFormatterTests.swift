import XCTest
@testable import FitBuddy

/// Unit tests for the 1RM formatter (US-9, #42).
final class OneRepMaxFormatterTests: XCTestCase {
    /// The half kilogram is the point: plates come in 1.25 kg pairs, and this
    /// is the digit `VolumeFormatter` would round away.
    func testHalfKilogramsSurvive() {
        XCTAssertEqual(OneRepMaxFormatter.kilograms(107.5), "107.5")
        XCTAssertEqual(OneRepMaxFormatter.kilograms(62.5), "62.5")
    }

    /// A whole number carries no decimal — "100.0" reads as a measurement.
    func testWholeKilogramsCarryNoDecimal() {
        XCTAssertEqual(OneRepMaxFormatter.kilograms(100), "100")
        XCTAssertEqual(OneRepMaxFormatter.kilograms(80), "80")
    }

    /// Epley produces long fractions; one decimal is all the precision the
    /// estimate has.
    func testLongFractionsAreCutToOneDecimal() {
        XCTAssertEqual(OneRepMaxFormatter.kilograms(116.66666), "116.7")
        XCTAssertEqual(OneRepMaxFormatter.kilograms(102.24), "102.2")
    }

    /// Foundation rounds a tie to the even digit, so `102.25` becomes `102.2`
    /// rather than `102.3`. Recorded rather than worked around: the value is
    /// an estimate to one decimal, and a tenth of a kilogram either way says
    /// nothing about the training.
    func testATieRoundsToTheEvenDigit() {
        XCTAssertEqual(OneRepMaxFormatter.kilograms(102.25), "102.2")
        XCTAssertEqual(OneRepMaxFormatter.kilograms(102.35), "102.4")
    }
}

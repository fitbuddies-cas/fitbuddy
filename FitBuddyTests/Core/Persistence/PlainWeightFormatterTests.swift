import XCTest
@testable import FitBuddy

/// Unit tests for `PlainWeightFormatter` (#173): one unambiguous spelling of
/// a weight, whatever the device locale.
final class PlainWeightFormatterTests: XCTestCase {
    func testWholeWeightsDropTheirDecimals() {
        XCTAssertEqual(PlainWeightFormatter.string(60), "60")
        XCTAssertEqual(PlainWeightFormatter.string(100), "100")
    }

    func testFractionsKeepOnlyTheDigitsTheyNeed() {
        XCTAssertEqual(PlainWeightFormatter.string(62.5), "62.5")
        XCTAssertEqual(PlainWeightFormatter.string(61.25), "61.25")
    }

    func testWeightsAreRoundedToTwoDecimalsByDefault() {
        XCTAssertEqual(PlainWeightFormatter.string(61.254), "61.25")
        XCTAssertEqual(PlainWeightFormatter.rounded(61.256), 61.26)
    }

    func testFewerDecimalsCanBeRequested() {
        XCTAssertEqual(PlainWeightFormatter.string(72.9166, decimals: 1), "72.9")
        XCTAssertEqual(PlainWeightFormatter.string(69.96, decimals: 1), "70")
    }

    func testTheSpellingIgnoresTheDeviceLocale() {
        XCTAssertFalse(PlainWeightFormatter.string(62.5).contains(","))
        XCTAssertFalse(PlainWeightFormatter.string(12_500).contains("'"))
    }
}

import XCTest
@testable import FitBuddy

/// Unit tests for `PlainNumberFormatter` (#173, #249): one unambiguous
/// spelling of a number, whatever the device locale.
final class PlainNumberFormatterTests: XCTestCase {
    func testWholeWeightsDropTheirDecimals() {
        XCTAssertEqual(PlainNumberFormatter.string(60), "60")
        XCTAssertEqual(PlainNumberFormatter.string(100), "100")
    }

    func testFractionsKeepOnlyTheDigitsTheyNeed() {
        XCTAssertEqual(PlainNumberFormatter.string(62.5), "62.5")
        XCTAssertEqual(PlainNumberFormatter.string(61.25), "61.25")
    }

    func testWeightsAreRoundedToTwoDecimalsByDefault() {
        XCTAssertEqual(PlainNumberFormatter.string(61.254), "61.25")
        XCTAssertEqual(PlainNumberFormatter.rounded(61.256), 61.26)
    }

    func testFewerDecimalsCanBeRequested() {
        XCTAssertEqual(PlainNumberFormatter.string(72.9166, decimals: 1), "72.9")
        XCTAssertEqual(PlainNumberFormatter.string(69.96, decimals: 1), "70")
    }

    func testTheSpellingIgnoresTheDeviceLocale() {
        XCTAssertFalse(PlainNumberFormatter.string(62.5).contains(","))
        XCTAssertFalse(PlainNumberFormatter.string(12_500).contains("'"))
    }
}

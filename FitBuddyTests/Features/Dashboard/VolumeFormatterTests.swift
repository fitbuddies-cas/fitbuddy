import XCTest
@testable import FitBuddy

final class VolumeFormatterTests: XCTestCase {
    func testFullFormDropsFractions() {
        XCTAssertEqual(VolumeFormatter.full(248_419.6), 248_420.formatted(.number))
        XCTAssertEqual(VolumeFormatter.full(0), "0")
    }

    func testCompactFormUsesOneDecimalBelowTenThousand() {
        XCTAssertEqual(VolumeFormatter.compact(4_820), "4.8k")
        XCTAssertEqual(VolumeFormatter.compact(1_000), "1k")
    }

    func testCompactFormDropsDecimalsAboveTenThousand() {
        XCTAssertEqual(VolumeFormatter.compact(46_320), "46k")
        XCTAssertEqual(VolumeFormatter.compact(248_420), "248k")
    }

    func testCompactFormLeavesSmallValuesUntouched() {
        XCTAssertEqual(VolumeFormatter.compact(640), "640")
        XCTAssertEqual(VolumeFormatter.compact(0), "0")
    }
}

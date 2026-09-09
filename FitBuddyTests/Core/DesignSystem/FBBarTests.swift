import XCTest
@testable import FitBuddy

/// The share bar's fraction clamp (#98). A fraction reaches the capsule as a
/// frame width, so a value that is not a real number is a layout error, not a
/// cosmetic one.
final class FBBarTests: XCTestCase {
    func testAFractionInsideTheRangeIsKept() {
        XCTAssertEqual(FBBar.clamped(0.25), 0.25)
    }

    func testValuesOutsideTheRangeAreClamped() {
        XCTAssertEqual(FBBar.clamped(-1), 0)
        XCTAssertEqual(FBBar.clamped(1.5), 1)
    }

    /// `min`/`max` alone let a NaN through — `max(.nan, 0)` is `.nan` in Swift.
    func testNaNAndInfinityReadAsEmptyRatherThanPropagating() {
        XCTAssertEqual(FBBar.clamped(.nan), 0)
        XCTAssertEqual(FBBar.clamped(.infinity), 0)
        XCTAssertEqual(FBBar.clamped(-.infinity), 0)
    }
}

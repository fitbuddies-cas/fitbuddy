import XCTest
@testable import FitBuddy

final class CountFormatterTests: XCTestCase {
    func testSingularHasNoPluralS() {
        XCTAssertEqual(CountFormatter.labelled(1, singular: "set"), "1 set")
        XCTAssertEqual(CountFormatter.labelled(1, singular: "exercise"), "1 exercise")
    }

    func testEveryOtherCountIsPlural() {
        XCTAssertEqual(CountFormatter.labelled(0, singular: "set"), "0 sets")
        XCTAssertEqual(CountFormatter.labelled(21, singular: "set"), "21 sets")
        XCTAssertEqual(CountFormatter.labelled(6, singular: "exercise"), "6 exercises")
    }
}

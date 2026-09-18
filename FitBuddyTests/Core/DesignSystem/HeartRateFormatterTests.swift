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

    /// A heart rate stays inside three digits, so no locale moves a digit —
    /// asserted so the shared formatter rule is not quietly dropped.
    func testTheLocaleLeavesAHeartRateUnchanged() {
        XCTAssertEqual(HeartRateFormatter.display(148, locale: german), "148 bpm")
    }

    func testThePlainFormIsLocaleFree() {
        XCTAssertEqual(HeartRateFormatter.plain(148), "148 bpm")
        XCTAssertEqual(HeartRateFormatter.plain(62.4), "62 bpm")
    }
}

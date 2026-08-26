import XCTest
@testable import FitBuddy

/// Unit tests for `CooldownFormatter` — the «Next analysis available in Xh Ym»
/// label (#31 AC3).
final class CooldownFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func remaining(_ seconds: TimeInterval) -> String? {
        CooldownFormatter.remaining(until: now.addingTimeInterval(seconds), now: now)
    }

    func testFormatsHoursAndMinutes() {
        XCTAssertEqual(remaining(5 * 3600 + 12 * 60), "5h 12m")
    }

    func testFormatsFullCooldownWindow() {
        XCTAssertEqual(remaining(AnalysisCooldownStore.duration), "6h 0m")
    }

    func testDropsHoursBelowOneHour() {
        XCTAssertEqual(remaining(12 * 60), "12m")
    }

    /// Rounded up, so the label never reads "0m" while the button is still
    /// disabled.
    func testRoundsPartialMinutesUp() {
        XCTAssertEqual(remaining(61), "2m")
        XCTAssertEqual(remaining(1), "1m")
    }

    func testCarriesRoundedMinutesIntoHours() {
        XCTAssertEqual(remaining(3600 + 59 * 60 + 30), "2h 0m")
    }

    func testReturnsNilOnceElapsed() {
        XCTAssertNil(remaining(0))
        XCTAssertNil(remaining(-60))
    }

    func testMessageWrapsRemainingTime() {
        XCTAssertEqual(
            CooldownFormatter.message(until: now.addingTimeInterval(2 * 3600), now: now),
            "Next analysis available in 2h 0m"
        )
    }

    func testMessageIsNilWithoutCooldown() {
        XCTAssertNil(CooldownFormatter.message(until: nil, now: now))
        XCTAssertNil(CooldownFormatter.message(until: now.addingTimeInterval(-1), now: now))
    }
}

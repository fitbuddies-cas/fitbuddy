import XCTest
@testable import FitBuddy

/// Unit tests for `CooldownFormatter` — the «New analysis available in 45s»
/// label (#31 AC3, #117).
final class CooldownFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_788_000_000)

    private func remaining(_ seconds: TimeInterval) -> String? {
        CooldownFormatter.remaining(until: now.addingTimeInterval(seconds), now: now)
    }

    func testFormatsSeconds() {
        XCTAssertEqual(remaining(45), "45s")
    }

    func testFormatsTheFullLock() {
        XCTAssertEqual(remaining(AnalysisRateLimitStore.duration), "60s")
    }

    /// Rounded up, so the label never reads "0s" while the button is still
    /// disabled.
    func testRoundsPartialSecondsUp() {
        XCTAssertEqual(remaining(0.2), "1s")
        XCTAssertEqual(remaining(44.1), "45s")
    }

    func testReturnsNilOnceElapsed() {
        XCTAssertNil(remaining(0))
        XCTAssertNil(remaining(-60))
    }

    /// Nothing counts in minutes or hours any more: the lock is 60s, and an
    /// "Xh Ym" label over it could never move.
    func testEvenALongLeftoverStaysInSeconds() {
        XCTAssertEqual(remaining(3_600), "3600s")
    }

    func testMessageWrapsRemainingTime() {
        XCTAssertEqual(
            CooldownFormatter.message(until: now.addingTimeInterval(45), now: now),
            "New analysis available in 45s"
        )
    }

    func testMessageIsNilWithoutAnActiveLock() {
        XCTAssertNil(CooldownFormatter.message(until: nil, now: now))
        XCTAssertNil(CooldownFormatter.message(until: now.addingTimeInterval(-1), now: now))
    }
}

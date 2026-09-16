import XCTest
@testable import FitBuddy

/// Unit tests for `SetMetricFormatter` (#98). The point of the type is that a
/// metric Hevy never logged stays absent instead of becoming a zero, so every
/// function is tested for `nil` as well as for its formatting.
final class SetMetricFormatterTests: XCTestCase {
    // MARK: - Weight

    func testWeightKeepsHalfKiloSteps() {
        XCTAssertEqual(SetMetricFormatter.weight(62.5), "62.5 kg")
    }

    func testWeightDropsATrailingZero() {
        XCTAssertEqual(SetMetricFormatter.weight(60), "60 kg")
    }

    /// A bodyweight set has no weight; "0 kg" would claim it had one.
    func testWeightIsNilWhenNoneWasLogged() {
        XCTAssertNil(SetMetricFormatter.weight(nil))
    }

    // MARK: - Reps

    func testRepsAgreeInNumber() {
        XCTAssertEqual(SetMetricFormatter.reps(8), "8 reps")
        XCTAssertEqual(SetMetricFormatter.reps(1), "1 rep")
    }

    func testRepsAreNilWhenNoneWereLogged() {
        XCTAssertNil(SetMetricFormatter.reps(nil))
    }

    // MARK: - Distance

    func testDistanceStaysInMetresBelowAKilometre() {
        XCTAssertEqual(SetMetricFormatter.distance(800), "800 m")
        XCTAssertEqual(SetMetricFormatter.distance(999), "999 m")
    }

    func testDistanceSwitchesToKilometres() {
        XCTAssertEqual(SetMetricFormatter.distance(1_000), "1.0 km")
        XCTAssertEqual(SetMetricFormatter.distance(5_400), "5.4 km")
    }

    func testDistanceIsNilWhenNoneWasLogged() {
        XCTAssertNil(SetMetricFormatter.distance(nil))
    }

    // MARK: - Duration

    func testDurationReadsLikeAStopwatch() {
        XCTAssertEqual(SetMetricFormatter.duration(45), "0:45")
        XCTAssertEqual(SetMetricFormatter.duration(90), "1:30")
        XCTAssertEqual(SetMetricFormatter.duration(600), "10:00")
    }

    func testDurationGainsAnHoursComponent() {
        XCTAssertEqual(SetMetricFormatter.duration(3_600), "1:00:00")
        XCTAssertEqual(SetMetricFormatter.duration(3_725), "1:02:05")
    }

    func testDurationIsNilWhenNoneWasLoggedOrItIsNegative() {
        XCTAssertNil(SetMetricFormatter.duration(nil))
        XCTAssertNil(SetMetricFormatter.duration(-1))
    }

    func testAZeroDurationIsStillADuration() {
        XCTAssertEqual(SetMetricFormatter.duration(0), "0:00")
    }

    // MARK: - RPE

    func testRPEKeepsTheHalfStep() {
        XCTAssertEqual(SetMetricFormatter.rpe(9.5), "RPE 9.5")
        XCTAssertEqual(SetMetricFormatter.rpe(8), "RPE 8")
    }

    func testRPEIsNilWhenNoneWasLogged() {
        XCTAssertNil(SetMetricFormatter.rpe(nil))
    }
}

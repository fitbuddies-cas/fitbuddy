import XCTest
@testable import FitBuddy

/// Unit tests for the Epley estimate (US-9 AC1, #41).
final class OneRepMaxTests: XCTestCase {
    /// The formula itself: `weight × (1 + reps / 30)`.
    func testEpleyMatchesTheFormula() throws {
        let estimate = try XCTUnwrap(OneRepMax.epley(weightKg: 100, reps: 5))
        XCTAssertEqual(estimate, 100 * (1 + 5.0 / 30), accuracy: 0.000_1)
    }

    /// A single rep is already the maximum — the formula must not inflate it.
    func testASingleRepIsItsOwnMaximumPlusTheFormulaShare() throws {
        let estimate = try XCTUnwrap(OneRepMax.epley(weightKg: 120, reps: 1))
        XCTAssertEqual(estimate, 124, accuracy: 0.000_1)
    }

    /// More reps at the same weight must project higher, or the curve would
    /// read a harder session as a worse one.
    func testMoreRepsAtTheSameWeightProjectHigher() throws {
        let five = try XCTUnwrap(OneRepMax.epley(weightKg: 100, reps: 5))
        let eight = try XCTUnwrap(OneRepMax.epley(weightKg: 100, reps: 8))
        XCTAssertGreaterThan(eight, five)
    }

    /// A bodyweight or cardio set has no load to project from. Treating the
    /// missing weight as 0 would put a 0 kg point on the curve — a wrong
    /// number where there should be none.
    func testSetsWithoutTheTwoNumbersHaveNoEstimate() {
        XCTAssertNil(OneRepMax.epley(weightKg: nil, reps: 8))
        XCTAssertNil(OneRepMax.epley(weightKg: 100, reps: nil))
        XCTAssertNil(OneRepMax.epley(weightKg: nil, reps: nil))
    }

    /// Zero weight is a bodyweight set, zero reps a set that was started and
    /// not completed. Neither is a lift, and the formula would hand back the
    /// bare weight for the second one.
    func testZeroWeightOrZeroRepsHaveNoEstimate() {
        XCTAssertNil(OneRepMax.epley(weightKg: 0, reps: 10))
        XCTAssertNil(OneRepMax.epley(weightKg: 100, reps: 0))
    }

    /// The set-shaped overload reads the same two numbers volume reads.
    func testReadsASetThroughTheSameTwoNumbersAsVolume() throws {
        let set = SetDetail(
            index: 0,
            type: .normal,
            weightKg: 60,
            reps: 10,
            distanceMeters: nil,
            durationSeconds: nil,
            rpe: nil
        )

        let estimate = try XCTUnwrap(OneRepMax.epley(of: set))

        XCTAssertEqual(estimate, 80, accuracy: 0.000_1)
    }
}

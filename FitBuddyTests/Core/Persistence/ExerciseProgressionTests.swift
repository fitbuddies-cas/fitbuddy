import XCTest
@testable import FitBuddy

/// Unit tests for the two verdicts US-9 draws from a progression series:
/// "enough to plot" (AC3) and "plateaued" (AC2).
final class ExerciseProgressionTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    // MARK: - Plottable (AC3)

    func testTwoSessionsAreEnoughToPlot() {
        XCTAssertTrue(makeProgression([100, 102]).isPlottable)
    }

    /// One point is a dot, not a curve — AC3 asks for the hint instead.
    func testOneSessionIsNotPlottable() {
        XCTAssertFalse(makeProgression([100]).isPlottable)
    }

    func testAMovementWithoutUsableSessionsIsNotPlottable() {
        XCTAssertFalse(makeProgression([]).isPlottable)
    }

    // MARK: - Plateau (AC2)

    /// Three sessions after the best one, none of them reaching it.
    func testThreeSessionsWithoutANewBestArePlateaued() {
        XCTAssertTrue(makeProgression([100, 98, 99, 97]).isPlateaued)
    }

    /// The last session beats everything before it — that is progress, however
    /// flat the two before it were.
    func testANewBestInTheLastSessionEndsThePlateau() {
        XCTAssertFalse(makeProgression([100, 98, 99, 101]).isPlateaued)
    }

    /// Read as "no new peak in three sessions", not as "three times down":
    /// these three rise against each other and still reach nothing the lifter
    /// had not already done.
    func testRisingSessionsThatNeverReachTheOldBestArePlateaued() {
        XCTAssertTrue(makeProgression([90, 100, 95, 98, 99]).isPlateaued)
    }

    /// Equalling the old best is not beating it. A repeated top set means the
    /// movement has stopped moving, which is exactly what the badge says.
    func testMatchingTheOldBestIsStillAPlateau() {
        XCTAssertTrue(makeProgression([100, 100, 100, 100]).isPlateaued)
    }

    /// With only three sessions the first of them set the best, so there is
    /// nothing earlier they failed to beat — a movement needs a fourth session
    /// before it can stall.
    func testThreeSessionsAloneCannotBeAPlateau() {
        XCTAssertFalse(makeProgression([100, 100, 100]).isPlateaued)
    }

    func testTooFewSessionsAreNeverAPlateau() {
        XCTAssertFalse(makeProgression([]).isPlateaued)
        XCTAssertFalse(makeProgression([100]).isPlateaued)
        XCTAssertFalse(makeProgression([100, 95]).isPlateaued)
    }

    /// Only the three most recent sessions are asked about: an old stall the
    /// lifter has since broken out of must not keep the badge on screen.
    func testAnOlderStallDoesNotCountOnceProgressResumed() {
        XCTAssertFalse(makeProgression([100, 98, 97, 99, 105]).isPlateaued)
    }

    // MARK: - Summary values

    func testBestAndLatestReadFromTheSeries() {
        let progression = makeProgression([100, 110, 105])

        XCTAssertEqual(progression.bestEstimateKg, 110)
        XCTAssertEqual(progression.latestEstimateKg, 105)
    }

    func testAnEmptySeriesHasNoBestOrLatest() {
        XCTAssertNil(makeProgression([]).bestEstimateKg)
        XCTAssertNil(makeProgression([]).latestEstimateKg)
    }

    // MARK: - Helpers

    /// A progression whose points are one day apart, oldest first.
    private func makeProgression(_ estimates: [Double]) -> ExerciseProgression {
        ExerciseProgression(
            id: "bench",
            title: "Bench Press (Barbell)",
            points: estimates.enumerated().map { offset, estimate in
                ProgressionPoint(
                    sessionStart: reference.addingTimeInterval(Double(offset) * 86_400),
                    estimatedOneRepMaxKg: estimate,
                    weightKg: estimate * 0.8,
                    reps: 8
                )
            }
        )
    }
}

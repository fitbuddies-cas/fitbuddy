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

    // MARK: - Curve and history (#163)

    /// Every point comes from a session, and the order survives.
    func testThePointsAreDerivedFromTheSessions() {
        let progression = makeProgression([100, 104, 102])

        XCTAssertEqual(progression.points.count, progression.sessions.count)
        XCTAssertEqual(
            progression.points.map(\.sessionStart),
            progression.sessions.map(\.sessionStart)
        )
    }

    /// A session Epley cannot project from stays in the history and leaves no
    /// point — the case a rowing machine or a plank produces, and the reason
    /// the two counts are allowed to differ (#163).
    func testASessionWithoutALoadIsInTheHistoryButNotOnTheCurve() {
        let progression = ExerciseProgression(
            id: "row",
            title: "Rowing Machine",
            sessions: [
                ExerciseHistoryEntry(
                    sessionStart: reference,
                    sets: [SetDetail(index: 0, type: .normal, weightKg: nil, reps: nil,
                                     distanceMeters: 2_000, durationSeconds: 480, rpe: nil)]
                ),
            ]
        )

        XCTAssertEqual(progression.sessions.count, 1)
        XCTAssertTrue(progression.points.isEmpty)
        XCTAssertFalse(progression.isPlottable)
    }

    /// Mixed: a movement trained with load and once without still plots only
    /// what it can.
    func testOnlySessionsWithALoadReachTheCurve() {
        let withLoad = [session(100, daysAfterReference: 0), session(104, daysAfterReference: 2)]
        let withoutLoad = ExerciseHistoryEntry(
            sessionStart: reference.addingTimeInterval(86_400),
            sets: [SetDetail(index: 0, type: .normal, weightKg: nil, reps: 15,
                             distanceMeters: nil, durationSeconds: nil, rpe: nil)]
        )
        let progression = ExerciseProgression(
            id: "bench",
            title: "Bench Press (Barbell)",
            sessions: [withLoad[0], withoutLoad, withLoad[1]]
        )

        XCTAssertEqual(progression.sessions.count, 3)
        XCTAssertEqual(progression.points.count, 2)
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

    /// A progression whose sessions are one day apart, oldest first.
    private func makeProgression(_ estimates: [Double]) -> ExerciseProgression {
        ExerciseProgression(
            id: "bench",
            title: "Bench Press (Barbell)",
            sessions: estimates.enumerated().map { offset, estimate in
                session(estimate, daysAfterReference: offset)
            }
        )
    }

    /// A session whose Epley estimate is exactly `estimate`.
    ///
    /// 30 reps at half the weight: the formula's factor is then `1 + 30/30`,
    /// so the round trip is a division and a multiplication by two — exact in
    /// binary, which keeps these tests about the plateau rule instead of about
    /// floating-point noise.
    private func session(_ estimate: Double, daysAfterReference days: Int) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            sessionStart: reference.addingTimeInterval(Double(days) * 86_400),
            sets: [
                SetDetail(index: 0, type: .normal, weightKg: estimate / 2, reps: 30,
                          distanceMeters: nil, durationSeconds: nil, rpe: nil),
            ]
        )
    }

}

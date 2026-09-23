import XCTest
@testable import FitBuddy

/// The 2-for-2 rule of ADR-013 (#232): the rep target beaten by two or more
/// on the last working set of the two most recent sessions — met, not met,
/// or not checkable for want of a target.
final class TwoForTwoConditionTests: XCTestCase {
    func testBeatenByTwoInBothSessionsIsMet() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 12, target: 10)]),
            session(2, sets: [set(0, reps: 12, target: 10)]),
        ])
        XCTAssertEqual(verdict, .met)
    }

    /// One extra rep is form on the day; the rule wants two.
    func testBeatenByOneIsNotMet() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 12, target: 10)]),
            session(2, sets: [set(0, reps: 11, target: 10)]),
        ])
        XCTAssertEqual(verdict, .notMet)
    }

    /// Two in a row: a success three sessions ago followed by a miss does
    /// not count, and neither does a miss followed by one success.
    func testOnlyTheTwoMostRecentSessionsCount() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 12, target: 10)]),
            session(2, sets: [set(0, reps: 10, target: 10)]),
            session(3, sets: [set(0, reps: 12, target: 10)]),
        ])
        XCTAssertEqual(verdict, .notMet)
    }

    func testASingleSessionIsNotMet() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 15, target: 10)]),
        ])
        XCTAssertEqual(verdict, .notMet)
    }

    /// Nothing attempted, nothing to check — and nothing to name as a target.
    func testNoWorkingSetAtAllIsNotCheckable() {
        XCTAssertEqual(TwoForTwoCondition.evaluate(sessions: []), .notCheckable)
        XCTAssertEqual(
            TwoForTwoCondition.evaluate(sessions: [session(1, sets: [set(0, type: .warmup, reps: 10, target: 8)])]),
            .notCheckable
        )
    }

    /// A single session without a target is not checkable, not "not met":
    /// the not-met line names the target, and there is none (#232 review).
    func testASingleSessionWithoutATargetIsNotCheckable() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 15, target: nil)]),
        ])
        XCTAssertEqual(verdict, .notCheckable)
    }

    /// A missing target is a state of its own, never read as met — even
    /// when the reps would have cleared any plausible target.
    func testAMissingTargetIsNotCheckable() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 20, target: nil)]),
            session(2, sets: [set(0, reps: 20, target: 10)]),
        ])
        XCTAssertEqual(verdict, .notCheckable)
    }

    /// The rule reads the last working set, not the best one.
    func testTheLastWorkingSetIsTheOneCompared() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 12, target: 10), set(1, reps: 12, target: 10)]),
            session(2, sets: [set(0, reps: 13, target: 10), set(1, reps: 10, target: 10)]),
        ])
        XCTAssertEqual(verdict, .notMet)
    }

    /// Warm-ups are not attempts at the target, wherever they sit.
    func testWarmUpsAreSkippedWhenFindingTheLastWorkingSet() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 12, target: 10), set(1, type: .warmup, reps: 3, target: 10)]),
            session(2, sets: [set(0, reps: 12, target: 10), set(1, type: .warmup, reps: 3, target: 10)]),
        ])
        XCTAssertEqual(verdict, .met)
    }

    /// A session holding only warm-ups does not enter the pair: the two
    /// sessions with working sets around it are what is compared.
    func testAWarmUpOnlySessionIsNotOneOfThePair() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 12, target: 10)]),
            session(2, sets: [set(0, reps: 12, target: 10)]),
            session(3, sets: [set(0, type: .warmup, reps: 10, target: 10)]),
        ])
        XCTAssertEqual(verdict, .met)
    }

    /// A set without a weight is not a working set, so a bodyweight finisher
    /// after the last loaded set does not become the set compared.
    func testAnUnloadedSetIsNotTheLastWorkingSet() {
        let verdict = TwoForTwoCondition.evaluate(sessions: [
            session(1, sets: [set(0, reps: 12, target: 10), set(1, weightKg: nil, reps: 5, target: 10)]),
            session(2, sets: [set(0, reps: 12, target: 10), set(1, weightKg: nil, reps: 5, target: 10)]),
        ])
        XCTAssertEqual(verdict, .met)
    }

    // MARK: - Latest target

    func testTheLatestTargetIsTheLastWorkingSetsOfTheMostRecentSession() {
        let target = TwoForTwoCondition.latestTarget(in: [
            session(1, sets: [set(0, reps: 12, target: 8)]),
            session(2, sets: [set(0, reps: 12, target: 10), set(1, reps: 10, target: 12)]),
        ])
        XCTAssertEqual(target, 12)
    }

    func testNoTargetOnTheLatestSessionIsNone() {
        let target = TwoForTwoCondition.latestTarget(in: [
            session(1, sets: [set(0, reps: 12, target: 8)]),
            session(2, sets: [set(0, reps: 12, target: nil)]),
        ])
        XCTAssertNil(target)
    }

    // MARK: - Helpers

    private func session(_ day: Int, sets: [SetDetail]) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            workoutID: "w-\(day)",
            sessionStart: Date(timeIntervalSince1970: 1_750_000_000 + Double(day) * 86_400),
            sets: sets
        )
    }

    private func set(
        _ index: Int, type: SetType = .normal, weightKg: Double? = 60, reps: Int?, target: Int?
    ) -> SetDetail {
        SetDetail(
            index: index, type: type, weightKg: weightKg, reps: reps,
            distanceMeters: nil, durationSeconds: nil, rpe: nil, targetReps: target
        )
    }
}

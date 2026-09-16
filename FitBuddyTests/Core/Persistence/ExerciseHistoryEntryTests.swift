import XCTest
@testable import FitBuddy

/// Unit tests for one session of a movement (#163).
final class ExerciseHistoryEntryTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    // MARK: - Derived values

    /// The best *counted* set defines the estimate — a heavy warm-up must not.
    func testTheBestCountedSetDefinesTheEstimate() throws {
        let entry = ExerciseHistoryEntry(
            workoutID: "w-1",
            sessionStart: reference,
            sets: [
                set(index: 0, type: .warmup, weight: 140, reps: 10),
                set(index: 1, type: .normal, weight: 100, reps: 5),
                set(index: 2, type: .normal, weight: 90, reps: 8),
            ]
        )

        let best = try XCTUnwrap(entry.bestSet)
        XCTAssertEqual(best.weightKg, 100)
        XCTAssertEqual(best.reps, 5)
        XCTAssertEqual(try XCTUnwrap(entry.estimatedOneRepMaxKg), 100 * (1 + 5.0 / 30), accuracy: 0.000_1)
    }

    func testVolumeAndCountedTallyExcludeWarmUps() {
        let entry = ExerciseHistoryEntry(
            workoutID: "w-1",
            sessionStart: reference,
            sets: [
                set(index: 0, type: .warmup, weight: 60, reps: 10),
                set(index: 1, type: .normal, weight: 100, reps: 5),
            ]
        )

        XCTAssertEqual(entry.volumeKg, 500)
        XCTAssertEqual(entry.countedSetCount, 1)
        // The warm-up is still in the list — the screen shows it, marked.
        XCTAssertEqual(entry.sets.count, 2)
    }

    // MARK: - Sessions the curve cannot use

    /// A rowing machine logs distance and time. Epley has nothing to work
    /// from, so the session has no estimate and no point — but it is still a
    /// session, and the history is the only place it can appear.
    func testACardioSessionHasNoEstimateAndNoPoint() {
        let entry = ExerciseHistoryEntry(
            workoutID: "w-1",
            sessionStart: reference,
            sets: [set(index: 0, type: .normal, distance: 2_000, duration: 480)]
        )

        XCTAssertNil(entry.estimatedOneRepMaxKg)
        XCTAssertNil(entry.bestSet)
        XCTAssertNil(entry.progressionPoint)
        XCTAssertEqual(entry.totalDistanceMeters, 2_000)
        XCTAssertEqual(entry.totalDurationSeconds, 480)
    }

    /// Bodyweight work: reps but no load, so again no estimate — and the reps
    /// are what the row has left to show.
    func testABodyweightSessionKeepsItsReps() {
        let entry = ExerciseHistoryEntry(
            workoutID: "w-1",
            sessionStart: reference,
            sets: [
                set(index: 0, type: .normal, weight: nil, reps: 12),
                set(index: 1, type: .normal, weight: nil, reps: 10),
            ]
        )

        XCTAssertNil(entry.estimatedOneRepMaxKg)
        XCTAssertEqual(entry.totalReps, 22)
        XCTAssertNil(entry.totalDistanceMeters)
    }

    // MARK: - Identity

    /// Two workouts can carry the same start — a manual correction in Hevy, a
    /// double import. Identified by the date they would collide in `ForEach`
    /// and open and close together; identified by the workout they do not.
    func testTwoSessionsAtTheSameInstantStayDistinct() {
        let first = ExerciseHistoryEntry(
            workoutID: "w-1",
            sessionStart: reference,
            sets: [set(index: 0, type: .normal, weight: 100, reps: 5)]
        )
        let second = ExerciseHistoryEntry(
            workoutID: "w-2",
            sessionStart: reference,
            sets: [set(index: 0, type: .normal, weight: 90, reps: 5)]
        )

        XCTAssertEqual(first.sessionStart, second.sessionStart)
        XCTAssertNotEqual(first.id, second.id)
    }

    // MARK: - The point the curve reads

    func testASessionWithLoadContributesItsPoint() throws {
        let entry = ExerciseHistoryEntry(
            workoutID: "w-1",
            sessionStart: reference,
            sets: [set(index: 0, type: .normal, weight: 100, reps: 5)]
        )

        let point = try XCTUnwrap(entry.progressionPoint)
        XCTAssertEqual(point.sessionStart, reference)
        XCTAssertEqual(point.weightKg, 100)
        XCTAssertEqual(point.reps, 5)
        XCTAssertEqual(point.estimatedOneRepMaxKg, try XCTUnwrap(entry.estimatedOneRepMaxKg))
    }

    // MARK: - Helpers

    private func set(
        index: Int,
        type: SetType,
        weight: Double? = nil,
        reps: Int? = nil,
        distance: Double? = nil,
        duration: Int? = nil
    ) -> SetDetail {
        SetDetail(
            index: index,
            type: type,
            weightKg: weight,
            reps: reps,
            distanceMeters: distance,
            durationSeconds: duration,
            rpe: nil
        )
    }
}

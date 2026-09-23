import XCTest
@testable import FitBuddy

/// Decoding tests for `GET /v1/routines` and the target a prescribed set
/// resolves to (#240) — the fallback chain ADR-013's 2-for-2 rule reads.
final class HevyRoutineDTOTests: XCTestCase {
    private func decode(_ payload: [String: Any]) throws -> HevyRoutineDTO {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder.hevy.decode(HevyRoutineDTO.self, from: data)
    }

    private func decodeSet(_ payload: [String: Any]) throws -> HevyRoutineSetDTO {
        let routine = try decode(HevyPayloadFactory.routine(
            id: "r-1",
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000),
            exercises: [HevyPayloadFactory.routineExercise(templateID: "05293BCA", sets: [payload])]
        ))
        return try XCTUnwrap(routine.exercises.first?.sets.first)
    }

    // MARK: - Target resolution

    /// The top of the range is the target: exceeding the bottom of `8–12` by
    /// two reps is landing inside the range, not outgrowing it.
    func testRangeEndWinsOverStartAndReps() throws {
        let set = try decodeSet(HevyPayloadFactory.routineSet(reps: 5, repRange: (8, 12)))
        XCTAssertEqual(set.targetReps, 12)
    }

    func testRangeStartIsTheFallbackWhenTheEndIsMissing() throws {
        let set = try decodeSet(HevyPayloadFactory.routineSet(reps: 5, repRange: (8, nil)))
        XCTAssertEqual(set.targetReps, 8)
    }

    /// What every routine observed on the live API carried: `reps` set and
    /// `rep_range` null.
    func testSingleRepsIsTheFallbackWhenThereIsNoRange() throws {
        let set = try decodeSet(HevyPayloadFactory.routineSet(reps: 10))
        XCTAssertEqual(set.targetReps, 10)
    }

    /// A timed or distance set prescribes nothing to beat — `nil` is the
    /// answer, not an error.
    func testNoTargetIsAValidState() throws {
        let set = try decodeSet(HevyPayloadFactory.routineSet(reps: nil, repRange: (nil, nil)))
        XCTAssertNil(set.targetReps)
    }

    func testWholeNumbersSentAsDecimalsStillResolve() throws {
        let set = try decodeSet([
            "type": "normal",
            "reps": 10.0,
            "rep_range": ["start": 8.0, "end": 12.0],
        ])
        XCTAssertEqual(set.targetReps, 12)
    }

    // MARK: - Set type

    /// The response schema types `type` as a description string, not an
    /// enum: a value this build does not know must read as unknown, not fail
    /// the routine.
    func testUnknownSetTypeFallsBackInsteadOfFailing() throws {
        let set = try decodeSet(HevyPayloadFactory.routineSet(type: "amrap", reps: 10))
        XCTAssertEqual(set.setType, .unknown)
        XCTAssertEqual(set.targetReps, 10)
    }

    func testMissingSetTypeReadsAsUnknown() throws {
        let set = try decodeSet(["reps": 10])
        XCTAssertEqual(set.setType, .unknown)
    }

    // MARK: - Routine

    func testDecodesIdUpdatedAtAndExercises() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let routine = try decode(HevyPayloadFactory.routine(id: "r-1", updatedAt: updatedAt))

        XCTAssertEqual(routine.id, "r-1")
        XCTAssertEqual(routine.title, "Push Day")
        XCTAssertEqual(routine.updatedAt, updatedAt)
        XCTAssertEqual(routine.exercises.map(\.exerciseTemplateID), ["05293BCA"])
        XCTAssertEqual(routine.exercises.first?.sets.map(\.targetReps), [10, 12])
    }

    func testMissingIdFailsDecoding() {
        XCTAssertThrowsError(try decode(["title": "Push Day", "exercises": []]))
    }

    func testMissingOptionalFieldsDecodeToDefaults() throws {
        let routine = try decode(["id": "r-1"])
        XCTAssertNil(routine.title)
        XCTAssertNil(routine.updatedAt)
        XCTAssertEqual(routine.exercises, [])
    }

    // MARK: - Matching a logged exercise to a prescribed one

    /// The n-th logged occurrence of a movement belongs to the n-th
    /// prescribed one: a heavy block and a back-off block of the same squat
    /// each get their own targets.
    func testTheSameMovementListedTwiceIsMatchedByOccurrence() throws {
        let routine = try decode(HevyPayloadFactory.routine(id: "r-1", updatedAt: Date(), exercises: [
            HevyPayloadFactory.routineExercise(templateID: "SQUAT", sets: [HevyPayloadFactory.routineSet(reps: 5)]),
            HevyPayloadFactory.routineExercise(templateID: "BENCH", sets: [HevyPayloadFactory.routineSet(reps: 8)]),
            HevyPayloadFactory.routineExercise(templateID: "SQUAT", sets: [HevyPayloadFactory.routineSet(reps: 10)]),
        ]))

        XCTAssertEqual(routine.exercise(templateID: "SQUAT", occurrence: 0)?.targetReps(forSet: 0, warmUp: false), 5)
        XCTAssertEqual(routine.exercise(templateID: "SQUAT", occurrence: 1)?.targetReps(forSet: 0, warmUp: false), 10)
        XCTAssertNil(routine.exercise(templateID: "SQUAT", occurrence: 2), "Logged a third time: nothing prescribed")
        XCTAssertNil(routine.exercise(templateID: "ROW", occurrence: 0), "Swapped in on the day: nothing prescribed")
    }

    /// An extra set the user added on the day had no target to beat.
    func testASetBeyondThePrescribedOnesHasNoTarget() throws {
        let routine = try decode(HevyPayloadFactory.routine(id: "r-1", updatedAt: Date()))
        let exercise = try XCTUnwrap(routine.exercises.first)

        XCTAssertEqual(exercise.targetReps(forSet: 0, warmUp: true), 10)
        XCTAssertEqual(exercise.targetReps(forSet: 0, warmUp: false), 12)
        XCTAssertNil(exercise.targetReps(forSet: 1, warmUp: false))
        XCTAssertNil(exercise.targetReps(forSet: 1, warmUp: true))
    }

    /// Matched per kind: the first working set is compared against the
    /// first prescribed working set, whatever the routine lists before it.
    func testWorkingSetsAreMatchedToWorkingSetsAcrossTheWarmUps() throws {
        let routine = try decode(HevyPayloadFactory.routine(id: "r-1", updatedAt: Date(), exercises: [
            HevyPayloadFactory.routineExercise(templateID: "SQUAT", sets: [
                HevyPayloadFactory.routineSet(type: "warmup", reps: 8),
                HevyPayloadFactory.routineSet(type: "warmup", reps: 5),
                HevyPayloadFactory.routineSet(type: "normal", reps: 3),
                HevyPayloadFactory.routineSet(type: "normal", reps: 3),
            ]),
        ]))
        let exercise = try XCTUnwrap(routine.exercises.first)

        XCTAssertEqual(exercise.targetReps(forSet: 0, warmUp: false), 3)
        XCTAssertEqual(exercise.targetReps(forSet: 1, warmUp: true), 5)
    }
}

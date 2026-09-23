import XCTest
@testable import FitBuddy

/// Decoding tests for the Hevy wire format and its mapping onto the
/// normalized `Activity` (#34) — the tolerances that keep one odd workout from
/// failing a whole sync.
final class HevyWorkoutDTOTests: XCTestCase {
    private func decode(_ payload: [String: Any]) throws -> HevyWorkoutDTO {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder.hevy.decode(HevyWorkoutDTO.self, from: data)
    }

    func testDecodesPlainISO8601Timestamps() throws {
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [],
        ])
        XCTAssertEqual(dto.startTime, ISO8601DateFormatter.hevyPlain.date(from: "2021-09-14T12:00:00Z"))
    }

    func testDecodesFractionalSecondTimestamps() throws {
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00.123Z",
            "exercises": [],
        ])
        XCTAssertNotNil(dto.startTime)
    }

    func testMissingStartTimeFailsDecoding() {
        XCTAssertThrowsError(try decode(["id": "w-1", "exercises": []]))
    }

    func testMissingOptionalFieldsDecodeToDefaults() throws {
        let dto = try decode(["id": "w-1", "start_time": "2021-09-14T12:00:00Z"])

        XCTAssertNil(dto.title)
        XCTAssertNil(dto.endTime)
        XCTAssertNil(dto.routineID)
        XCTAssertEqual(dto.exercises, [])

        let activity = dto.makeActivity()
        XCTAssertEqual(activity.title, "Workout")
        XCTAssertEqual(activity.exercises.count, 0)
        // Set explicitly by the mapping, not left to the default (#141).
        XCTAssertEqual(activity.source, .hevy)
    }

    func testWholeNumbersSentAsDecimalsStillDecode() throws {
        // Hevy types reps/duration as `number`, so `8` may arrive as `8.0`.
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [[
                "index": 0.0,
                "title": "Squat (Barbell)",
                "sets": [["index": 0.0, "type": "normal", "reps": 8.0, "duration_seconds": 90.0]],
            ]],
        ])

        let set = try XCTUnwrap(dto.exercises.first?.sets.first)
        XCTAssertEqual(set.reps, 8)
        XCTAssertEqual(set.durationSeconds, 90)
    }

    func testOutOfRangeNumbersDecodeToNilInsteadOfTrapping() throws {
        // The loose-number fallback exists to survive odd payloads, so a value
        // no `Int` can hold must drop the field rather than crash the app.
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [[
                "index": 0,
                "title": "Squat (Barbell)",
                "sets": [["index": 0, "type": "normal", "reps": 1e30, "duration_seconds": 1e30]],
            ]],
        ])

        let set = try XCTUnwrap(dto.exercises.first?.sets.first)
        XCTAssertNil(set.reps)
        XCTAssertNil(set.durationSeconds)
    }

    func testZeroDistanceAndDurationDecodeAsNotLogged() throws {
        // Hevy sends 0 instead of null for the metrics an exercise does not
        // use, which the detail row would otherwise print as "0 m · 0:00".
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [[
                "index": 0,
                "title": "Standing Calf Raise (Machine)",
                "sets": [[
                    "index": 0,
                    "type": "normal",
                    "weight_kg": 115.0,
                    "reps": 11,
                    "distance_meters": 0,
                    "duration_seconds": 0,
                ]],
            ]],
        ])

        let set = try XCTUnwrap(dto.makeActivity().exercises.first?.sets.first)
        XCTAssertNil(set.distanceMeters)
        XCTAssertNil(set.durationSeconds)
        XCTAssertEqual(set.weightKg, 115)
        XCTAssertEqual(set.reps, 11)
    }

    func testLoggedDistanceAndDurationSurviveDecoding() throws {
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [[
                "index": 0,
                "title": "Rowing Machine",
                "sets": [["index": 0, "type": "normal", "distance_meters": 3500.0, "duration_seconds": 1206]],
            ]],
        ])

        let set = try XCTUnwrap(dto.makeActivity().exercises.first?.sets.first)
        XCTAssertEqual(set.distanceMeters, 3_500)
        XCTAssertEqual(set.durationSeconds, 1_206)
    }

    /// A zero weight is a bodyweight set and a zero rep count a set that was
    /// started and not completed — neither is a missing value, so neither is
    /// dropped alongside the zero distance/duration.
    func testZeroWeightAndRepsAreKept() throws {
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [[
                "index": 0,
                "title": "Pull Up",
                "sets": [["index": 0, "type": "normal", "weight_kg": 0.0, "reps": 0]],
            ]],
        ])

        let set = try XCTUnwrap(dto.makeActivity().exercises.first?.sets.first)
        XCTAssertEqual(set.weightKg, 0)
        XCTAssertEqual(set.reps, 0)
    }

    func testUnknownSetTypeDoesNotFailDecoding() throws {
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [[
                "index": 0,
                "title": "Squat (Barbell)",
                "sets": [["index": 0, "type": "cluster"]],
            ]],
        ])

        let set = try XCTUnwrap(dto.makeActivity().exercises.first?.sets.first)
        XCTAssertEqual(set.type, .unknown)
        XCTAssertFalse(set.type.countsTowardsVolume)
    }

    func testMissingIndicesFallBackToPayloadOrder() throws {
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [[
                "title": "Squat (Barbell)",
                "sets": [["type": "normal"], ["type": "normal"]],
            ]],
        ])

        let exercise = try XCTUnwrap(dto.makeActivity().exercises.first)
        XCTAssertEqual(exercise.index, 0)
        XCTAssertEqual(exercise.sets.map(\.index).sorted(), [0, 1])
    }

    /// Hevy's `index` is optional per entry, so a payload may carry it for one
    /// exercise and omit it for the next. Reading it would then hand two
    /// entries the same index — and that index is `ActivityExercise.id`, so
    /// `ForEach` would drop a card and the sort by index would be arbitrary.
    func testIndicesStayUniqueWhenThePayloadNumbersOnlySomeEntries() throws {
        let dto = try decode([
            "id": "w-1",
            "start_time": "2021-09-14T12:00:00Z",
            "exercises": [
                [
                    "index": 1,
                    "title": "Squat (Barbell)",
                    "sets": [["index": 1, "type": "normal"], ["type": "normal"]],
                ],
                ["title": "Bench Press (Barbell)", "sets": [["type": "normal"]]],
            ],
        ])

        let activity = dto.makeActivity()
        XCTAssertEqual(activity.exercises.map(\.index), [0, 1])
        let first = try XCTUnwrap(activity.exercises.first)
        XCTAssertEqual(first.sets.map(\.index).sorted(), [0, 1])
    }

    func testPageDefaultsToASinglePageWhenCountIsMissing() throws {
        let data = try JSONSerialization.data(withJSONObject: ["workouts": []])
        let page = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)

        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.pageCount, 1)
        XCTAssertEqual(page.workouts, [])
    }

    // MARK: - Routine targets (#240)

    /// A workout logged without a routine is the common case, and the spec
    /// does not mark `routine_id` nullable: decoding it strictly would fail
    /// the whole page at the first free workout.
    func testAWorkoutWithoutARoutineDecodesAndCarriesNoTargets() throws {
        let dto = try decode(HevyPayloadFactory.workout(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000)))
        XCTAssertNil(dto.routineID)

        let activity = dto.makeActivity(routine: nil)
        XCTAssertNil(activity.routineID)
        XCTAssertNil(activity.routineUpdatedAt)
        XCTAssertEqual(activity.exercises.first?.sets.map(\.targetReps), [nil, nil])
    }

    /// Hevy sends `routine_id: null` too, on a workout whose routine is gone.
    func testANullRoutineIdDecodesAsNone() throws {
        var payload = HevyPayloadFactory.workout(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000))
        payload["routine_id"] = NSNull()
        XCTAssertNil(try decode(payload).routineID)
    }

    func testTargetsAreSnapshottedByPositionWithTheRoutineTimestamp() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        let dto = try decode(HevyPayloadFactory.workout(id: "w-1", start: updatedAt, routineID: "r-1"))
        let routineData = try JSONSerialization.data(
            withJSONObject: HevyPayloadFactory.routine(id: "r-1", updatedAt: updatedAt)
        )
        let routine = try JSONDecoder.hevy.decode(HevyRoutineDTO.self, from: routineData)

        let activity = dto.makeActivity(routine: routine)

        XCTAssertEqual(activity.routineID, "r-1")
        XCTAssertEqual(activity.routineUpdatedAt, updatedAt)
        // Warm-up slot and working slot line up with the prescribed ones.
        XCTAssertEqual(activity.exercises.first?.sets.map(\.targetReps), [10, 12])
    }

    /// A warm-up skipped on the day does not shift the working targets: the
    /// routine prescribes a warm-up and a working set, the user logged the
    /// working set only, and it still gets the working target.
    func testASkippedWarmUpDoesNotShiftTheWorkingTargets() throws {
        var payload = HevyPayloadFactory.workout(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000), routineID: "r-1")
        var exercises = try XCTUnwrap(payload["exercises"] as? [[String: Any]])
        var sets = try XCTUnwrap(exercises[0]["sets"] as? [[String: Any]])
        sets.removeFirst()
        exercises[0]["sets"] = sets
        payload["exercises"] = exercises
        let routineData = try JSONSerialization.data(
            withJSONObject: HevyPayloadFactory.routine(id: "r-1", updatedAt: Date(timeIntervalSince1970: 1_750_000_000))
        )
        let routine = try JSONDecoder.hevy.decode(HevyRoutineDTO.self, from: routineData)

        let activity = try decode(payload).makeActivity(routine: routine)

        XCTAssertEqual(activity.exercises.first?.sets.map(\.type), [.normal])
        XCTAssertEqual(activity.exercises.first?.sets.map(\.targetReps), [12])
    }

    /// The id is kept even when the routine could not be fetched (deleted
    /// at the source): the session still says what it was logged against,
    /// and the empty targets say the plan is gone.
    func testARoutineHevyNoLongerHasLeavesTheIdAndNoTargets() throws {
        let dto = try decode(HevyPayloadFactory.workout(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000), routineID: "r-gone"))

        let activity = dto.makeActivity(routine: nil)

        XCTAssertEqual(activity.routineID, "r-gone")
        XCTAssertNil(activity.routineUpdatedAt)
        XCTAssertEqual(activity.exercises.first?.sets.map(\.targetReps), [nil, nil])
    }
}

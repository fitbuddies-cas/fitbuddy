import XCTest
@testable import FitBuddy

/// Decoding tests for the Hevy wire format — the tolerances that keep one odd
/// workout from failing a whole sync.
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
        XCTAssertEqual(dto.exercises, [])

        let workout = dto.makeWorkout()
        XCTAssertEqual(workout.title, "Workout")
        XCTAssertEqual(workout.exercises.count, 0)
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

        let set = try XCTUnwrap(dto.makeWorkout().exercises.first?.sets.first)
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

        let set = try XCTUnwrap(dto.makeWorkout().exercises.first?.sets.first)
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

        let set = try XCTUnwrap(dto.makeWorkout().exercises.first?.sets.first)
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

        let set = try XCTUnwrap(dto.makeWorkout().exercises.first?.sets.first)
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

        let exercise = try XCTUnwrap(dto.makeWorkout().exercises.first)
        XCTAssertEqual(exercise.index, 0)
        XCTAssertEqual(exercise.sets.map(\.index).sorted(), [0, 1])
    }

    /// Hevy's `index` is optional per entry, so a payload may carry it for one
    /// exercise and omit it for the next. Reading it would then hand two
    /// entries the same index — and that index is `ExerciseDetail.id`, so
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

        let workout = dto.makeWorkout()
        XCTAssertEqual(workout.exercises.map(\.index), [0, 1])
        let first = try XCTUnwrap(workout.exercises.first)
        XCTAssertEqual(first.sets.map(\.index).sorted(), [0, 1])
    }

    func testPageDefaultsToASinglePageWhenCountIsMissing() throws {
        let data = try JSONSerialization.data(withJSONObject: ["workouts": []])
        let page = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)

        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.pageCount, 1)
        XCTAssertEqual(page.workouts, [])
    }
}

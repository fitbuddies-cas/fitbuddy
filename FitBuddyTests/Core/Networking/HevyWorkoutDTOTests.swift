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

    func testPageDefaultsToASinglePageWhenCountIsMissing() throws {
        let data = try JSONSerialization.data(withJSONObject: ["workouts": []])
        let page = try JSONDecoder.hevy.decode(HevyWorkoutsPage.self, from: data)

        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.pageCount, 1)
        XCTAssertEqual(page.workouts, [])
    }
}

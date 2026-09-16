import XCTest
@testable import FitBuddy

final class PolarExerciseDTOTests: XCTestCase {
    /// AccessLink responses use underscore-separated keys.
    private static let fullExercise = Data(#"""
    {
      "id": "aQlC83",
      "upload_time": "2008-10-13T10:40:02Z",
      "start_time": "2008-10-13T10:40:02",
      "start_time_utc_offset": 180,
      "duration": "PT2H44M30S",
      "distance": 1600.2,
      "heart_rate": { "average": 129, "maximum": 147 },
      "training_load": 143.22,
      "calories": 530,
      "sport": "OTHER",
      "detailed_sport_info": "TREADMILL_RUNNING"
    }
    """#.utf8)

    func testMapsEveryFieldOntoTheNormalizedActivity() throws {
        let dto = try JSONDecoder().decode(PolarExerciseDTO.self, from: Self.fullExercise)

        let activity = try XCTUnwrap(dto.makeActivity())

        XCTAssertEqual(activity.id, "polar-aQlC83")
        XCTAssertEqual(activity.source, .polar)
        XCTAssertEqual(activity.title, "Treadmill Running")
        // 10:40:02 local at +03:00 → 07:40:02 UTC.
        XCTAssertEqual(
            activity.startTime,
            ISO8601DateFormatter().date(from: "2008-10-13T07:40:02Z")
        )
        XCTAssertEqual(activity.endTime, activity.startTime.addingTimeInterval(2 * 3600 + 44 * 60 + 30))
        XCTAssertTrue(activity.exercises.isEmpty)

        let metrics = try XCTUnwrap(activity.metrics)
        XCTAssertEqual(metrics.averageHeartRate, 129)
        XCTAssertEqual(metrics.maximumHeartRate, 147)
        XCTAssertEqual(metrics.activeCalories, 530)
        XCTAssertEqual(metrics.distanceMeters, 1600.2)
        XCTAssertEqual(metrics.durationSeconds, 9870)
        XCTAssertEqual(metrics.trainingLoad, 143.22)
        XCTAssertEqual(metrics.sport, "TREADMILL_RUNNING")
    }

    func testDropsAnExerciseThatHasNoParseableStartTime() throws {
        let json = Data(#"{ "id": "x", "start_time": "not-a-date" }"#.utf8)

        let dto = try JSONDecoder().decode(PolarExerciseDTO.self, from: json)

        XCTAssertNil(dto.makeActivity())
    }

    func testMissingOffsetIsTreatedAsUTC() throws {
        let json = Data(#"{ "id": "x", "start_time": "2020-01-01T12:00:00" }"#.utf8)

        let activity = try XCTUnwrap(
            try JSONDecoder().decode(PolarExerciseDTO.self, from: json).makeActivity()
        )

        XCTAssertEqual(activity.startTime, ISO8601DateFormatter().date(from: "2020-01-01T12:00:00Z"))
        XCTAssertNil(activity.endTime)
    }

    func testAnExerciseWithNoRecordedMetricsMapsToNilMetricsRatherThanAnEmptyBlock() throws {
        let json = Data(#"{ "id": "x", "start_time": "2020-01-01T12:00:00", "start_time_utc_offset": 0 }"#.utf8)

        let activity = try XCTUnwrap(
            try JSONDecoder().decode(PolarExerciseDTO.self, from: json).makeActivity()
        )

        XCTAssertNil(activity.metrics)
    }

    func testDurationParserHandlesPartialComponentsAndRejectsGarbage() {
        XCTAssertEqual(PolarDuration.seconds(from: "PT44M"), 2640)
        XCTAssertEqual(PolarDuration.seconds(from: "PT30S"), 30)
        XCTAssertEqual(PolarDuration.seconds(from: "PT1H30M"), 5400)
        XCTAssertNil(PolarDuration.seconds(from: "P1DT1H"))
        XCTAssertNil(PolarDuration.seconds(from: "PT"))
        XCTAssertNil(PolarDuration.seconds(from: "PT10"))
    }
}

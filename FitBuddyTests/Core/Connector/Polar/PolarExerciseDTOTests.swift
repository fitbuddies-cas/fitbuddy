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

        let metrics = try XCTUnwrap(activity.cardio)
        XCTAssertEqual(metrics.averageHeartRate, 129)
        XCTAssertEqual(metrics.maxHeartRate, 147)
        XCTAssertEqual(metrics.activeCalories, 530)
        XCTAssertEqual(metrics.distanceMeters, 1600.2)
        XCTAssertEqual(metrics.durationSeconds, 9870)
        XCTAssertEqual(metrics.trainingLoad, 143.22)
        // Derived, not reported: Polar sends neither speed nor pace at
        // session level, but the pair it does send determines them.
        XCTAssertEqual(
            try XCTUnwrap(metrics.averageSpeedMetersPerSecond),
            1600.2 / 9870,
            accuracy: 0.0001
        )
        XCTAssertEqual(activity.kind, .run)
    }

    // MARK: - Training Load Pro (#244)

    /// A session from a watch with Training Load Pro, shaped like a real
    /// AccessLink response: the exercise uses underscore keys, the block
    /// inside it hyphenated ones — in the same object.
    private static let trainingLoadProExercise = Data(#"""
    {
      "id": "bQlD94",
      "upload_time": "2026-09-12T14:05:11Z",
      "polar_user": "https://www.polaraccesslink.com/v3/users/1",
      "device": "Polar Vantage V3",
      "start_time": "2026-09-12T12:00:00",
      "start_time_utc_offset": 120,
      "duration": "PT1H15M0S",
      "distance": 38000.0,
      "heart_rate": { "average": 149, "maximum": 172 },
      "training_load": 148.0,
      "calories": 980,
      "sport": "CYCLING",
      "detailed_sport_info": "ROAD_CYCLING",
      "has_route": true,
      "training_load_pro": {
        "date": "2026-09-12",
        "cardio-load": 151.3,
        "muscle-load": 62.5,
        "perceived-load": 525.0,
        "cardio-load-interpretation": "HIGH",
        "muscle-load-interpretation": "MODERATE",
        "perceived-load-interpretation": "HIGH",
        "user-rpe": "RPE_HARD"
      }
    }
    """#.utf8)

    func testDecodesTheHyphenatedTrainingLoadProKeysInsideTheUnderscoredExercise() throws {
        let dto = try JSONDecoder().decode(PolarExerciseDTO.self, from: Self.trainingLoadProExercise)

        XCTAssertEqual(dto.cardioLoad, 151.3)
        XCTAssertEqual(dto.muscleLoad, 62.5)
        XCTAssertEqual(dto.perceivedLoad, 525.0)
        XCTAssertEqual(dto.userRPE, .hard)

        let cardio = try XCTUnwrap(dto.makeActivity()?.cardio)
        XCTAssertEqual(cardio.cardioLoad, 151.3)
        XCTAssertEqual(cardio.muscleLoad, 62.5)
        XCTAssertEqual(cardio.perceivedLoad, 525.0)
        XCTAssertEqual(cardio.userRPE, .hard)
        // The legacy figure stays where it was, next to the new ones.
        XCTAssertEqual(cardio.trainingLoad, 148.0)
        XCTAssertEqual(cardio.averageHeartRate, 149)
    }

    /// An older watch sends no `training_load_pro` at all. That is not an
    /// error: the session decodes, keeps its legacy load, and every Training
    /// Load Pro value is `nil`.
    func testASessionWithoutTrainingLoadProDecodesWithEveryProValueNil() throws {
        let dto = try JSONDecoder().decode(PolarExerciseDTO.self, from: Self.fullExercise)

        let cardio = try XCTUnwrap(dto.makeActivity()?.cardio)
        XCTAssertEqual(cardio.trainingLoad, 143.22)
        XCTAssertNil(cardio.cardioLoad)
        XCTAssertNil(cardio.muscleLoad)
        XCTAssertNil(cardio.perceivedLoad)
        XCTAssertNil(cardio.userRPE)
    }

    /// A block Polar filled only partly — no power meter, no rating — keeps
    /// what it has and leaves the rest `nil`.
    func testAPartialTrainingLoadProBlockKeepsWhatItHas() throws {
        let json = Data(#"""
        {
          "id": "x",
          "start_time": "2020-01-01T12:00:00",
          "training_load_pro": { "cardio-load": 80.0, "cardio-load-interpretation": "MODERATE" }
        }
        """#.utf8)

        let cardio = try XCTUnwrap(
            try JSONDecoder().decode(PolarExerciseDTO.self, from: json).makeActivity()?.cardio
        )

        XCTAssertEqual(cardio.cardioLoad, 80.0)
        XCTAssertNil(cardio.muscleLoad)
        XCTAssertNil(cardio.perceivedLoad)
        XCTAssertNil(cardio.userRPE)
    }

    /// A rating label this build does not know must not fail the session: it
    /// reads as `.unknown`, and so does Polar's own `UNKNOWN`.
    func testAnUnknownUserRPELabelReadsAsUnknown() throws {
        for label in ["RPE_SOMETHING_NEW", "UNKNOWN"] {
            let json = Data(#"""
            {
              "id": "x",
              "start_time": "2020-01-01T12:00:00",
              "training_load_pro": { "cardio-load": 80.0, "user-rpe": "\#(label)" }
            }
            """#.utf8)

            let dto = try JSONDecoder().decode(PolarExerciseDTO.self, from: json)

            XCTAssertEqual(dto.userRPE, .unknown, label)
            XCTAssertEqual(dto.cardioLoad, 80.0, label)
        }
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

        XCTAssertNil(activity.cardio)
    }

    /// The derived speed needs both figures; without either, a division would
    /// be a guess (or a crash).
    func testAverageSpeedIsOmittedWhenDistanceOrDurationIsMissing() throws {
        let noDistance = Data(#"""
        { "id": "x", "start_time": "2020-01-01T12:00:00", "duration": "PT1H", "calories": 100 }
        """#.utf8)
        let noDuration = Data(#"""
        { "id": "x", "start_time": "2020-01-01T12:00:00", "distance": 5000 }
        """#.utf8)

        for json in [noDistance, noDuration] {
            let activity = try XCTUnwrap(
                try JSONDecoder().decode(PolarExerciseDTO.self, from: json).makeActivity()
            )
            XCTAssertNil(activity.cardio?.averageSpeedMetersPerSecond)
        }
    }

    /// Polar sends `distance: 0.0` for an indoor session it never measured
    /// spatially. Zero means "not logged", so it must not reach the dashboard
    /// as "0 m" where the duration belongs.
    func testAZeroDistanceIsTreatedAsNotLogged() throws {
        let json = Data(#"""
        { "id": "x", "start_time": "2020-01-01T12:00:00", "distance": 0, "duration": "PT1H" }
        """#.utf8)

        let activity = try XCTUnwrap(
            try JSONDecoder().decode(PolarExerciseDTO.self, from: json).makeActivity()
        )

        XCTAssertNil(activity.cardio?.distanceMeters)
        XCTAssertEqual(activity.cardio?.durationSeconds, 3_600)
    }

    /// And `PT0S` the same way round: a zero duration is one Polar never
    /// recorded, not a session that lasted no time.
    func testAZeroDurationIsTreatedAsNotLogged() throws {
        let json = Data(#"""
        { "id": "x", "start_time": "2020-01-01T12:00:00", "distance": 5000, "duration": "PT0S" }
        """#.utf8)

        let activity = try XCTUnwrap(
            try JSONDecoder().decode(PolarExerciseDTO.self, from: json).makeActivity()
        )

        XCTAssertNil(activity.cardio?.durationSeconds)
        XCTAssertEqual(activity.cardio?.distanceMeters, 5000)
    }

    // MARK: - Sport mapping (#180)

    func testSportLabelsMapOntoTheNormalizedKind() {
        let cases: [(sport: String?, detailed: String?, expected: ActivityKind)] = [
            ("RUNNING", nil, .run),
            ("JOGGING", nil, .run),
            (nil, "TREADMILL_RUNNING", .run),
            ("CYCLING", nil, .ride),
            ("MOUNTAIN_BIKING", nil, .ride),
            ("SWIMMING", nil, .swim),
            (nil, "OPEN_WATER_SWIMMING", .swim),
            ("HIKING", nil, .hike),
            ("WALKING", nil, .walk),
            ("NORDIC_WALKING", nil, .walk),
            ("STRENGTH_TRAINING", nil, .strength),
            ("OTHER_INDOOR", nil, .other),
            ("YOGA", nil, .other),
            (nil, nil, .other),
            // The detailed label is the finer one and is asked first…
            ("OTHER", "TREADMILL_RUNNING", .run),
            // …but an unrecognised one must not throw the coarse label away:
            // Polar keeps extending `detailed_sport_info`, and this session
            // belongs in the strength domain either way.
            ("STRENGTH_TRAINING", "FUNCTIONAL_TRAINING", .strength),
        ]

        for (sport, detailed, expected) in cases {
            XCTAssertEqual(
                PolarExerciseDTO.kind(sport: sport, detailed: detailed),
                expected,
                "\(sport ?? "nil") / \(detailed ?? "nil")"
            )
        }
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

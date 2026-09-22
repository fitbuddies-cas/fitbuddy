import XCTest
@testable import FitBuddy

/// `Activity` is the connector-facing wire/cache boundary (ADR-6), so its
/// `Codable` round-trip is what future connectors and any future persistence
/// of the normalized model rely on.
final class ActivityTests: XCTestCase {
    func testEncodeDecodeRoundTripPreservesTheFullHierarchy() throws {
        let set = ActivityExerciseSet(
            index: 0,
            type: .normal,
            weightKg: 80,
            reps: 5,
            rpe: 8
        )
        let exercise = ActivityExercise(index: 0, title: "Back Squat", notes: "felt heavy", sets: [set])
        let activity = Activity(
            id: "workout-1",
            title: "Leg Day",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600),
            exercises: [exercise]
        )

        let data = try JSONEncoder().encode(activity)
        let decoded = try JSONDecoder().decode(Activity.self, from: data)

        XCTAssertEqual(decoded, activity)
    }

    func testUnknownSetTypeRawValueDecodesToUnknownRatherThanFailing() throws {
        let json = Data(#"{"index":0,"typeRawValue":"some-future-type"}"#.utf8)

        let decoded = try JSONDecoder().decode(ActivityExerciseSet.self, from: json)

        XCTAssertEqual(decoded.type, .unknown)
    }

    /// Children carry no generated identifier, so the same source data mapped
    /// twice stays `==` — otherwise every re-sync would look like a change to
    /// `cached == fetched` and force SwiftUI to rebuild each `ForEach` row.
    func testTwoMappingsOfTheSameSourceDataCompareEqual() {
        func map() -> Activity {
            Activity(
                id: "workout-1",
                title: "Leg Day",
                startTime: Date(timeIntervalSince1970: 1_700_000_000),
                exercises: [
                    ActivityExercise(
                        index: 0,
                        title: "Back Squat",
                        sets: [ActivityExerciseSet(index: 0, type: .normal, weightKg: 80, reps: 5)]
                    )
                ]
            )
        }

        XCTAssertEqual(map(), map())
    }

    func testChildIdentityFollowsTheSourceOrderingRatherThanBeingGenerated() {
        let exercise = ActivityExercise(
            index: 2,
            title: "Back Squat",
            sets: [ActivityExerciseSet(index: 1, type: .normal)]
        )

        XCTAssertEqual(exercise.id, 2)
        XCTAssertEqual(exercise.sets[0].id, 1)
    }

    func testDefaultsProduceAnEmptyActivityWithNoExercises() {
        let activity = Activity(id: "empty", title: "Rest Day", startTime: .distantPast)

        XCTAssertNil(activity.endTime)
        XCTAssertEqual(activity.exercises, [])
    }

    // MARK: - Source (#141)

    /// Every activity before #141 was a Hevy one; the default keeps that true
    /// for every caller and fixture that predates the field.
    func testSourceDefaultsToHevy() {
        let activity = Activity(id: "w-1", title: "Leg Day", startTime: .distantPast)

        XCTAssertEqual(activity.source, .hevy)
    }

    func testSourceSurvivesTheCodableRoundTrip() throws {
        let activity = Activity(id: "strava:1", title: "Run", startTime: .distantPast, source: .strava)

        let data = try JSONEncoder().encode(activity)
        let decoded = try JSONDecoder().decode(Activity.self, from: data)

        XCTAssertEqual(decoded.source, .strava)
        XCTAssertEqual(decoded, activity)
    }

    func testActivitiesDifferingOnlyInSourceAreNotEqual() {
        let hevy = Activity(id: "1", title: "Run", startTime: .distantPast, source: .hevy)
        let strava = Activity(id: "1", title: "Run", startTime: .distantPast, source: .strava)

        XCTAssertNotEqual(hevy, strava)
    }

    // MARK: - Kind & cardio (#180)

    /// US-15 / #180 AC2: nothing about a Hevy workout changed — it is a
    /// strength session with no cardio block, without the mapping saying so.
    func testKindDefaultsToStrengthAndCardioToNone() {
        let activity = Activity(id: "w-1", title: "Leg Day", startTime: .distantPast)

        XCTAssertEqual(activity.kind, .strength)
        XCTAssertNil(activity.cardio)
    }

    func testKindAndCardioSurviveTheCodableRoundTrip() throws {
        let activity = Activity(
            id: "strava:1",
            title: "Trail Run",
            startTime: .distantPast,
            source: .strava,
            kind: .run,
            cardio: CardioMetrics(
                averageHeartRate: 148,
                maxHeartRate: 172,
                elevationGainMeters: 412.5,
                averageSpeedMetersPerSecond: 2.78,
                energyKilojoules: 920,
                perceivedEffort: 64,
                activeCalories: 530,
                distanceMeters: 10_400,
                durationSeconds: 3742,
                trainingLoad: 143.22
            )
        )

        let data = try JSONEncoder().encode(activity)
        let decoded = try JSONDecoder().decode(Activity.self, from: data)

        XCTAssertEqual(decoded, activity)
        XCTAssertEqual(decoded.kind, .run)
        XCTAssertEqual(decoded.cardio?.maxHeartRate, 172)
    }

    /// A sport a newer build knows and this one does not must not fail the
    /// whole activity — it reads as an unclassified session.
    func testAnUnknownKindRawValueDecodesToOther() throws {
        let json = Data(#"["hyrox","run"]"#.utf8)

        XCTAssertEqual(try JSONDecoder().decode([ActivityKind].self, from: json), [.other, .run])
    }

    func testOnlyTheEnduranceDisciplinesCountAsEndurance() {
        XCTAssertEqual(
            ActivityKind.allCases.filter(\.isEndurance),
            [.run, .ride, .swim, .hike, .walk]
        )
    }

    /// An all-`nil` block is not cardio data: the mapping hands out `nil`
    /// instead, so `cardio != nil` always means something was recorded.
    func testAnEmptyCardioBlockIsNotHandedOut() {
        XCTAssertNil(CardioMetrics().nonEmpty)
        XCTAssertNotNil(CardioMetrics(averageHeartRate: 120).nonEmpty)
    }
}

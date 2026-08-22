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

    func testUnknownSetTypeRawValueDecodesToUnknownRatherThanFailing() {
        let set = ActivityExerciseSet(index: 0, type: .normal)
        var mutable = set
        mutable.typeRawValue = "some-future-type"

        XCTAssertEqual(mutable.type, .unknown)
    }

    func testDefaultsProduceAnEmptyActivityWithNoExercises() {
        let activity = Activity(id: "empty", title: "Rest Day", startTime: .distantPast)

        XCTAssertNil(activity.endTime)
        XCTAssertEqual(activity.exercises, [])
    }
}

import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for the progression read against a real in-memory SwiftData
/// container (US-9 AC1, #41).
final class WorkoutStoreProgressionTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    private var container: ModelContainer!
    private var sut: WorkoutStore!

    override func setUp() async throws {
        try await super.setUp()
        container = try ModelContainerFactory.makeInMemory()
        sut = WorkoutStore(modelContainer: container)
    }

    override func tearDown() async throws {
        sut = nil
        container = nil
        try await super.tearDown()
    }

    func testUnknownMovementHasNoProgression() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [activity(id: "w-1", daysAgo: 2)])

        let progression = try await sut.exerciseProgression(id: "nothing-here", since: windowStart)

        XCTAssertNil(progression)
    }

    /// One point per session, oldest first — the order the chart plots in.
    func testOnePointPerSessionOldestFirst() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            activity(id: "w-1", daysAgo: 6, sets: [(100, 5)]),
            activity(id: "w-2", daysAgo: 3, sets: [(105, 5)]),
        ])

        let progression = try await XCTUnwrapAsync(
            try await sut.exerciseProgression(id: templateID, since: windowStart)
        )

        XCTAssertEqual(progression.points.count, 2)
        XCTAssertEqual(progression.points.map(\.sessionStart), [start(daysAgo: 6), start(daysAgo: 3)])
        XCTAssertEqual(progression.points.first?.estimatedOneRepMaxKg ?? 0, 100 * (1 + 5.0 / 30), accuracy: 0.000_1)
    }

    /// The best set of the day defines the point, not the last one — a
    /// back-off set after the top set must not read as a worse session.
    func testTheSessionsBestSetDefinesItsPoint() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            activity(id: "w-1", daysAgo: 2, sets: [(100, 5), (80, 8)]),
        ])

        let progression = try await XCTUnwrapAsync(
            try await sut.exerciseProgression(id: templateID, since: windowStart)
        )

        let point = try XCTUnwrap(progression.points.first)
        XCTAssertEqual(point.weightKg, 100)
        XCTAssertEqual(point.reps, 5)
    }

    /// Warm-ups are excluded here as they are everywhere else: a ramp-up set
    /// must not define the day's best on a light session.
    func testWarmUpSetsDoNotDefineAPoint() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            activity(id: "w-1", daysAgo: 2, sets: [(60, 10)], warmUpSets: [(140, 10)]),
        ])

        let progression = try await XCTUnwrapAsync(
            try await sut.exerciseProgression(id: templateID, since: windowStart)
        )

        let point = try XCTUnwrap(progression.points.first)
        XCTAssertEqual(point.weightKg, 60)
    }

    /// A session logged without weight or reps leaves no point behind — and
    /// that is not the same as the movement being absent, which is why the
    /// progression itself still comes back.
    func testASessionWithoutUsableSetsLeavesNoPoint() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            activity(id: "w-1", daysAgo: 2, sets: [(nil, nil)]),
        ])

        let progression = try await XCTUnwrapAsync(
            try await sut.exerciseProgression(id: templateID, since: windowStart)
        )

        XCTAssertTrue(progression.points.isEmpty)
        XCTAssertFalse(progression.isPlottable)
    }

    /// A movement performed twice inside one workout is still one session, or
    /// the plateau rule would count a single day as three.
    func testAMovementLoggedTwiceInOneSessionYieldsOnePoint() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            activity(id: "w-1", daysAgo: 2, sets: [(100, 5)], secondOccurrenceSets: [(110, 5)]),
        ])

        let progression = try await XCTUnwrapAsync(
            try await sut.exerciseProgression(id: templateID, since: windowStart)
        )

        XCTAssertEqual(progression.points.count, 1)
        XCTAssertEqual(progression.points.first?.weightKg, 110)
    }

    /// Sessions outside the window are none of this screen's business.
    func testSessionsBeforeTheWindowAreIgnored() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            activity(id: "old", daysAgo: 200, sets: [(200, 5)]),
            activity(id: "w-1", daysAgo: 2, sets: [(100, 5)]),
        ])

        let progression = try await XCTUnwrapAsync(
            try await sut.exerciseProgression(id: templateID, since: windowStart)
        )

        XCTAssertEqual(progression.points.count, 1)
        XCTAssertEqual(progression.points.first?.weightKg, 100)
    }

    /// The title follows the most recent session, as the exercise list does.
    func testTitleComesFromTheMostRecentSession() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            activity(id: "w-1", daysAgo: 6, sets: [(100, 5)], title: "Bench Press"),
            activity(id: "w-2", daysAgo: 3, sets: [(100, 5)], title: "Bench Press (Barbell)"),
        ])

        let progression = try await XCTUnwrapAsync(
            try await sut.exerciseProgression(id: templateID, since: windowStart)
        )

        XCTAssertEqual(progression.title, "Bench Press (Barbell)")
    }

    /// A Strava session sharing the movement's key contributes nothing: no
    /// weight, no reps, so at best an empty curve — and, alone, it must not
    /// even produce a titled progression with no points (US-5, #144).
    func testStravaSessionsAreIgnored() async throws {
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            Activity(
                id: "strava:1",
                title: "Morning Run",
                startTime: start(daysAgo: 2),
                source: .strava,
                exercises: [
                    ActivityExercise(index: 0, title: "Run", sets: [
                        ActivityExerciseSet(index: 0, type: .normal, distanceMeters: 5_000, durationSeconds: 1_800),
                    ]),
                ]
            ),
        ])
        let runKey = ExerciseSummary.key(templateID: nil, title: "Run")

        let progression = try await sut.exerciseProgression(id: runKey, since: windowStart)

        XCTAssertNil(progression)
    }

    // MARK: - Helpers

    private let templateID = "05293BCA"

    private var windowStart: Date { TrainingWindow.start(endingAt: reference) }

    private func start(daysAgo days: Int) -> Date {
        reference.addingTimeInterval(-Double(days) * 86_400)
    }

    /// An activity holding one exercise with the given working sets.
    private func activity(
        id: String,
        daysAgo days: Int,
        sets: [(Double?, Int?)] = [(100, 5)],
        warmUpSets: [(Double?, Int?)] = [],
        secondOccurrenceSets: [(Double?, Int?)]? = nil,
        title: String = "Bench Press (Barbell)"
    ) -> Activity {
        var exercises = [
            ActivityExercise(
                index: 0,
                title: title,
                templateID: templateID,
                sets: makeSets(warmUpSets, type: .warmup) + makeSets(sets, type: .normal)
            ),
        ]
        if let secondOccurrenceSets {
            exercises.append(
                ActivityExercise(
                    index: 1,
                    title: title,
                    templateID: templateID,
                    sets: makeSets(secondOccurrenceSets, type: .normal)
                )
            )
        }
        return Activity(id: id, title: "Session", startTime: start(daysAgo: days), exercises: exercises)
    }

    private func makeSets(_ values: [(Double?, Int?)], type: SetType) -> [ActivityExerciseSet] {
        values.enumerated().map { index, value in
            ActivityExerciseSet(index: index, type: type, weightKg: value.0, reps: value.1)
        }
    }

    /// `XCTUnwrap` over an `async` expression, so the call sites stay one line.
    private func XCTUnwrapAsync<T>(
        _ expression: @autoclosure () async throws -> T?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> T {
        let value = try await expression()
        return try XCTUnwrap(value, file: file, line: line)
    }
}

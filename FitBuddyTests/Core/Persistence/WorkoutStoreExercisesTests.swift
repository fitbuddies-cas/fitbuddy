import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for the exercise list's read path into the cache (US-7, #37),
/// run against a real in-memory SwiftData container.
final class WorkoutStoreExercisesTests: XCTestCase {
    private var container: ModelContainer!
    private var sut: WorkoutStore!

    /// Reference "now" for the window boundaries below.
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

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

    func testFoldsTheSameMovementAcrossSessions() async throws {
        try insert([
            makeWorkout(id: "w-1", start: reference, exercises: [
                (title: "Bench Press (Barbell)", templateID: "t-bench", sets: [
                    (type: .warmup, weight: 60, reps: 10),  // excluded
                    (type: .normal, weight: 100, reps: 8),  // 800
                ]),
            ]),
            makeWorkout(id: "w-2", start: reference.addingTimeInterval(-7 * 86_400), exercises: [
                (title: "Bench Press (Barbell)", templateID: "t-bench", sets: [
                    (type: .normal, weight: 90, reps: 10),  // 900
                ]),
            ]),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.count, 1)
        let bench = try XCTUnwrap(summaries.first)
        XCTAssertEqual(bench.title, "Bench Press (Barbell)")
        XCTAssertEqual(bench.muscleGroup, .chest)
        XCTAssertEqual(bench.sessionCount, 2)
        XCTAssertEqual(bench.countedSetCount, 2)
        XCTAssertEqual(bench.volumeKg, 1_700, accuracy: 0.001)
        XCTAssertEqual(bench.lastPerformed, reference)
    }

    /// Hevy's template id is the identity when the cache holds one, so a
    /// renamed exercise stays one row — under the name of the newest session.
    func testARenamedMovementStaysOneRowUnderItsNewestTitle() async throws {
        try insert([
            makeWorkout(id: "new", start: reference, exercises: [
                (title: "Incline Bench Press", templateID: "t-bench", sets: [(.normal, 100, 5)]),
            ]),
            makeWorkout(id: "old", start: reference.addingTimeInterval(-5 * 86_400), exercises: [
                (title: "Bench Press", templateID: "t-bench", sets: [(.normal, 100, 5)]),
            ]),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.map(\.title), ["Incline Bench Press"])
        XCTAssertEqual(summaries.first?.sessionCount, 2)
    }

    /// Without a template id the folded title decides, so the list does not
    /// split one movement into two rows over capitalisation.
    func testWithoutATemplateIDTheTitleFoldsCaseAndDiacritics() async throws {
        try insert([
            makeWorkout(id: "w-1", start: reference, exercises: [
                (title: "Lat Pulldown", templateID: nil, sets: [(.normal, 60, 10)]),
            ]),
            makeWorkout(id: "w-2", start: reference.addingTimeInterval(-86_400), exercises: [
                (title: "lat pulldown", templateID: nil, sets: [(.normal, 60, 10)]),
            ]),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.sessionCount, 2)
    }

    /// Two different movements are two rows even when they load the same
    /// muscle group.
    func testDifferentMovementsStayApart() async throws {
        try insert([
            makeWorkout(id: "w-1", start: reference, exercises: [
                (title: "Bench Press (Barbell)", templateID: "t-1", sets: [(.normal, 100, 5)]),
                (title: "Chest Fly (Dumbbell)", templateID: "t-2", sets: [(.normal, 20, 12)]),
            ]),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(Set(summaries.map(\.title)), ["Bench Press (Barbell)", "Chest Fly (Dumbbell)"])
    }

    /// A movement performed twice in one workout — Hevy allows it — is one
    /// session for that movement, with both blocks' sets counted.
    func testAMovementRepeatedInOneWorkoutCountsAsOneSession() async throws {
        try insert([
            makeWorkout(id: "w-1", start: reference, exercises: [
                (title: "Squat (Barbell)", templateID: "t-squat", sets: [(.normal, 100, 5)]),
                (title: "Squat (Barbell)", templateID: "t-squat", sets: [(.normal, 100, 5)]),
            ]),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.first?.sessionCount, 1)
        XCTAssertEqual(summaries.first?.countedSetCount, 2)
        XCTAssertEqual(try XCTUnwrap(summaries.first).volumeKg, 1_000, accuracy: 0.001)
    }

    func testIgnoresWorkoutsOutsideTheWindow() async throws {
        try insert([
            makeWorkout(id: "old", start: reference.addingTimeInterval(-100 * 86_400), exercises: [
                (title: "Deadlift (Barbell)", templateID: "t-dl", sets: [(.normal, 140, 3)]),
            ]),
            makeWorkout(id: "recent", start: reference.addingTimeInterval(-86_400), exercises: [
                (title: "Squat (Barbell)", templateID: "t-squat", sets: [(.normal, 100, 5)]),
            ]),
        ])

        let summaries = try await sut.exerciseSummaries(since: TrainingWindow.start(endingAt: reference))

        XCTAssertEqual(summaries.map(\.title), ["Squat (Barbell)"])
    }

    func testSortsByMostRecentlyPerformed() async throws {
        try insert([
            makeWorkout(id: "w-1", start: reference.addingTimeInterval(-10 * 86_400), exercises: [
                (title: "Squat (Barbell)", templateID: "t-squat", sets: [(.normal, 100, 5)]),
            ]),
            makeWorkout(id: "w-2", start: reference, exercises: [
                (title: "Bench Press (Barbell)", templateID: "t-bench", sets: [(.normal, 100, 5)]),
            ]),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.map(\.title), ["Bench Press (Barbell)", "Squat (Barbell)"])
    }

    func testAnEmptyCacheReturnsNothing() async throws {
        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertTrue(summaries.isEmpty)
    }

    // MARK: - Strava sessions (US-5, #144)

    /// A run is one "exercise" named after the sport with a single cardio
    /// set. Listed, it would read as a 0 kg movement over n sessions with a
    /// guessed muscle group — and fold into a Hevy exercise of the same title.
    ///
    /// Still true after #183 flipped the filter from the source to the sport:
    /// these runs are endurance either way.
    func testStravaSessionsStayOutOfTheListAndDoNotMergeWithAHevyMovement() async throws {
        try insert([
            makeWorkout(id: "hevy-1", start: reference, exercises: [
                (title: "Run", templateID: nil, sets: [(type: .normal, weight: nil, reps: nil)]),
            ]),
            makeStravaRun(id: "strava:1", start: reference.addingTimeInterval(-86_400)),
            makeStravaRun(id: "strava:2", start: reference.addingTimeInterval(-2 * 86_400)),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.count, 1)
        let run = try XCTUnwrap(summaries.first)
        XCTAssertEqual(run.sessionCount, 1, "only the Hevy session counts")
        XCTAssertEqual(run.countedSetCount, 1)
    }

    func testPolarSessionsStayOutOfTheList() async throws {
        try insert([
            makeWorkout(id: "hevy-1", start: reference, exercises: [
                (title: "Run", templateID: nil, sets: [(type: .normal, weight: nil, reps: nil)]),
            ]),
            makeStravaRun(id: "polar:1", start: reference.addingTimeInterval(-86_400), source: .polar),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries.first?.sessionCount, 1, "only the Hevy session counts")
    }

    // MARK: - Domain, not source (#183)

    /// The first of the two mismatches the review of #183 caught: a Hevy
    /// session of treadmill sets is endurance by `WorkoutSummary.isCardio`, so
    /// its session is described by the endurance section — but the source
    /// filter kept listing its "exercise" here, next to strength figures that
    /// do not contain it. Rule 6 tells the model to recommend only on this
    /// section, so the two have to cover the same sessions.
    func testAHevyCardioSessionIsNotListedAsAMovement() async throws {
        try insert([
            makeWorkout(id: "hevy-lift", start: reference, exercises: [
                (title: "Bench Press (Barbell)", templateID: "t-bench", sets: [(.normal, 100, 5)]),
            ]),
            Workout(
                id: "hevy-treadmill",
                title: "Treadmill",
                startTime: reference.addingTimeInterval(-86_400),
                exercises: [
                    Exercise(index: 0, title: "Treadmill", sets: [
                        ExerciseSet(index: 0, type: .normal, distanceMeters: 5_000, durationSeconds: 1_800),
                    ]),
                ]
            ),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.map(\.title), ["Bench Press (Barbell)"])
    }

    /// The other mismatch: a Strava `WeightTraining` session counts towards
    /// the strength figures since #183, so the movements it recorded belong in
    /// the section those figures are explained by.
    func testAStravaStrengthSessionIsListedAsAMovement() async throws {
        try insert([
            makeWorkout(id: "hevy-lift", start: reference, exercises: [
                (title: "Bench Press (Barbell)", templateID: "t-bench", sets: [(.normal, 100, 5)]),
            ]),
            Workout(
                id: "strava:gym",
                title: "Gym",
                startTime: reference.addingTimeInterval(-86_400),
                source: .strava,
                kind: .strength,
                exercises: [
                    Exercise(index: 0, title: "Gym", sets: [
                        ExerciseSet(index: 0, type: .normal, durationSeconds: 2_880),
                    ]),
                ]
            ),
        ])

        let summaries = try await sut.exerciseSummaries(since: .distantPast)

        XCTAssertEqual(summaries.map(\.title), ["Bench Press (Barbell)", "Gym"])
        XCTAssertEqual(summaries.last?.volumeKg, 0)
    }

    // MARK: - Helpers

    /// A run as a connector caches one. `kind` is explicit since #183: the
    /// column is written on every row, so leaving it at the model default
    /// would store "Strava says this is strength training", which is what the
    /// filter now — correctly — reads it as.
    private func makeStravaRun(
        id: String,
        start: Date,
        source: ConnectorSource = .strava,
        kind: ActivityKind = .run
    ) -> Workout {
        Workout(
            id: id,
            title: "Morning Run",
            startTime: start,
            source: source,
            kind: kind,
            exercises: [
                Exercise(index: 0, title: "Run", sets: [
                    ExerciseSet(index: 0, type: .normal, distanceMeters: 5_000, durationSeconds: 1_800),
                ]),
            ]
        )
    }

    private func insert(_ workouts: [Workout]) throws {
        let context = ModelContext(container)
        for workout in workouts {
            context.insert(workout)
        }
        try context.save()
    }

    private func makeWorkout(
        id: String,
        start: Date,
        exercises: [(title: String, templateID: String?, sets: [(type: SetType, weight: Double?, reps: Int?)])]
    ) -> Workout {
        Workout(
            id: id,
            title: "Session",
            startTime: start,
            exercises: exercises.enumerated().map { index, entry in
                Exercise(
                    index: index,
                    title: entry.title,
                    templateID: entry.templateID,
                    sets: entry.sets.enumerated().map { setIndex, set in
                        ExerciseSet(index: setIndex, type: set.type, weightKg: set.weight, reps: set.reps)
                    }
                )
            }
        )
    }
}

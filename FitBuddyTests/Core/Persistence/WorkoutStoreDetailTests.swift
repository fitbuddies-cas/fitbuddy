import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `WorkoutStore.workoutDetail(id:)` — the read path behind the
/// workout detail screen (#98).
///
/// The models are inserted directly rather than through
/// `replaceCachedWorkouts(with:)`: the cases that matter here are the ones the
/// Hevy payload cannot express — exercises stored out of order, a session with
/// no exercises, sets with no weight at all.
final class WorkoutStoreDetailTests: XCTestCase {
    private static let start = Date(timeIntervalSince1970: 1_750_000_000)

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

    // MARK: - Lookup

    /// A sync replaces the whole window, so the session behind an open screen
    /// can be gone. That is an answer, not an error.
    func testReturnsNilForAWorkoutThatIsNotCached() async throws {
        try insert(Self.pushDay(id: "w-1"))

        let detail = try await sut.workoutDetail(id: "w-2")

        XCTAssertNil(detail)
    }

    func testReturnsNilOnAnEmptyCache() async throws {
        let detail = try await sut.workoutDetail(id: "w-1")

        XCTAssertNil(detail)
    }

    /// Two cached sessions, one asked for: the predicate has to pick the right
    /// one rather than whichever the store returns first.
    func testReturnsTheRequestedWorkout() async throws {
        try insert(Self.pushDay(id: "w-1", title: "Push Day"))
        try insert(Self.pushDay(id: "w-2", title: "Leg Day"))

        let detail = try await sut.workoutDetail(id: "w-2")

        XCTAssertEqual(detail?.id, "w-2")
        XCTAssertEqual(detail?.title, "Leg Day")
    }

    // MARK: - Mapping

    func testCarriesTheSessionHeaderFields() async throws {
        try insert(Self.pushDay(id: "w-1"))

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)

        XCTAssertEqual(detail.title, "Push Day")
        XCTAssertEqual(detail.workoutDescription, "Felt strong")
        XCTAssertEqual(detail.startTime, Self.start)
        XCTAssertEqual(detail.endTime, Self.start.addingTimeInterval(3_600))
        XCTAssertEqual(detail.exerciseCount, 2)
    }

    func testCarriesTheExerciseFields() async throws {
        try insert(Self.pushDay(id: "w-1"))

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)
        let bench = try XCTUnwrap(detail.exercises.first)

        XCTAssertEqual(bench.title, "Bench Press (Barbell)")
        XCTAssertEqual(bench.notes, "Paused every first rep")
        XCTAssertEqual(bench.supersetID, 3)
        XCTAssertEqual(bench.muscleGroup, .chest)
    }

    func testCarriesEverySetMetricAsLogged() async throws {
        try insert(Self.pushDay(id: "w-1"))

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)
        let working = try XCTUnwrap(detail.exercises.first?.sets.last)

        XCTAssertEqual(working.type, .normal)
        XCTAssertEqual(working.weightKg, 100)
        XCTAssertEqual(working.reps, 8)
        XCTAssertEqual(working.rpe, 9.5)
        XCTAssertNil(working.distanceMeters)
        XCTAssertNil(working.durationSeconds)
    }

    /// A session Hevy recorded without exercises is still a session — the
    /// screen says so rather than treating it as missing.
    func testAWorkoutWithoutExercisesLoadsAsAnEmptyDetail() async throws {
        try insert(Workout(id: "w-1", title: "Empty", startTime: Self.start))

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)

        XCTAssertEqual(detail.exercises, [])
        XCTAssertEqual(detail.exerciseCount, 0)
        XCTAssertEqual(detail.volumeKg, 0)
        XCTAssertEqual(detail.countedSetCount, 0)
    }

    // MARK: - Ordering

    /// SwiftData does not guarantee the order of a to-many relationship, so
    /// the exercises are stored back to front here on purpose.
    func testExercisesComeBackInHevyOrder() async throws {
        try insert(
            Workout(id: "w-1", title: "Push Day", startTime: Self.start, exercises: [
                Exercise(index: 2, title: "Triceps Pushdown"),
                Exercise(index: 0, title: "Bench Press (Barbell)"),
                Exercise(index: 1, title: "Shoulder Press (Dumbbell)"),
            ])
        )

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)

        XCTAssertEqual(detail.exercises.map(\.index), [0, 1, 2])
        XCTAssertEqual(
            detail.exercises.map(\.title),
            ["Bench Press (Barbell)", "Shoulder Press (Dumbbell)", "Triceps Pushdown"]
        )
    }

    func testSetsComeBackInHevyOrder() async throws {
        try insert(
            Workout(id: "w-1", title: "Push Day", startTime: Self.start, exercises: [
                Exercise(index: 0, title: "Bench Press (Barbell)", sets: [
                    ExerciseSet(index: 2, type: .normal, weightKg: 100, reps: 6),
                    ExerciseSet(index: 0, type: .warmup, weightKg: 60, reps: 10),
                    ExerciseSet(index: 1, type: .normal, weightKg: 100, reps: 8),
                ]),
            ])
        )

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)
        let sets = try XCTUnwrap(detail.exercises.first?.sets)

        XCTAssertEqual(sets.map(\.index), [0, 1, 2])
        XCTAssertEqual(sets.map(\.reps), [10, 8, 6])
    }

    // MARK: - Volume

    /// Warm-ups stay visible on the screen but out of the numbers — the same
    /// rule the dashboard applies (`SetType.countsTowardsVolume`).
    func testWarmUpSetsAreShownButNotCounted() async throws {
        try insert(Self.pushDay(id: "w-1"))

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)
        let bench = try XCTUnwrap(detail.exercises.first)

        XCTAssertEqual(bench.sets.count, 2)
        XCTAssertEqual(bench.sets.map(\.type), [.warmup, .normal])
        XCTAssertEqual(bench.countedSetCount, 1)
        // 100 kg × 8 reps — the 60 kg warm-up is not in it.
        XCTAssertEqual(bench.volumeKg, 800)
    }

    /// A bodyweight or cardio set has no kg volume; treating its missing
    /// weight as 0 would be the same number with a worse meaning.
    func testSetsWithoutAWeightAddNoVolumeButStillCount() async throws {
        try insert(
            Workout(id: "w-1", title: "Push Day", startTime: Self.start, exercises: [
                Exercise(index: 0, title: "Dips", sets: [
                    ExerciseSet(index: 0, type: .normal, reps: 12),
                    ExerciseSet(index: 1, type: .normal, reps: 10),
                ]),
            ])
        )

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)
        let dips = try XCTUnwrap(detail.exercises.first)

        XCTAssertEqual(dips.volumeKg, 0)
        XCTAssertEqual(dips.countedSetCount, 2)
        XCTAssertEqual(dips.sets.map(\.weightKg), [nil, nil])
    }

    /// The header must agree with the cards under it, so the session totals
    /// are the sum of the exercises' own.
    func testSessionTotalsSumTheExercises() async throws {
        try insert(Self.pushDay(id: "w-1"))

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)

        // Bench 100×8, shoulder press 2 × 30×10.
        XCTAssertEqual(detail.volumeKg, 800 + 600)
        XCTAssertEqual(detail.countedSetCount, 3)
        XCTAssertEqual(detail.volumeKg, detail.exercises.reduce(0) { $0 + $1.volumeKg })
    }

    /// The detail and the dashboard read the same session, so their figures
    /// must not drift apart.
    func testTotalsMatchTheDashboardSummaryOfTheSameSession() async throws {
        try insert(Self.pushDay(id: "w-1"))

        let loaded = try await sut.workoutDetail(id: "w-1")
        let detail = try XCTUnwrap(loaded)
        let summaries = try await sut.workoutSummaries(since: Self.start.addingTimeInterval(-86_400))
        let summary = try XCTUnwrap(summaries.first)

        XCTAssertEqual(detail.volumeKg, summary.volumeKg)
        XCTAssertEqual(detail.countedSetCount, summary.countedSetCount)
        XCTAssertEqual(detail.exerciseCount, summary.exerciseCount)
    }

    // MARK: - Helpers

    /// Writes `workout` through a second context on the same container — the
    /// store itself only reads.
    private func insert(_ workout: Workout) throws {
        let context = ModelContext(container)
        context.insert(workout)
        try context.save()
    }

    /// A two-exercise session: a barbell lift with one warm-up and one working
    /// set, plus a dumbbell press with two working sets.
    private static func pushDay(id: String, title: String = "Push Day") -> Workout {
        Workout(
            id: id,
            title: title,
            workoutDescription: "Felt strong",
            startTime: start,
            endTime: start.addingTimeInterval(3_600),
            exercises: [
                Exercise(
                    index: 0,
                    title: "Bench Press (Barbell)",
                    notes: "Paused every first rep",
                    templateID: "05293BCA",
                    supersetID: 3,
                    sets: [
                        ExerciseSet(index: 0, type: .warmup, weightKg: 60, reps: 10),
                        ExerciseSet(index: 1, type: .normal, weightKg: 100, reps: 8, rpe: 9.5),
                    ]
                ),
                Exercise(index: 1, title: "Shoulder Press (Dumbbell)", sets: [
                    ExerciseSet(index: 0, type: .normal, weightKg: 30, reps: 10),
                    ExerciseSet(index: 1, type: .normal, weightKg: 30, reps: 10),
                ]),
            ]
        )
    }
}

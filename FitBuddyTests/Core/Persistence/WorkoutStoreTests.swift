import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for `WorkoutStore` against real SwiftData containers — in-memory
/// for the mapping/replacement behaviour, on-disk for the app-kill guarantee
/// (issue #25 AC2). The store is written from normalized `Activity` values
/// (#34), so no provider payload appears here.
final class WorkoutStoreTests: XCTestCase {
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

    // MARK: - Mapping

    func testStoresWorkoutHierarchyFromActivities() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(with: [
            ActivityFactory.activity(id: "w-1", start: start),
        ])

        let context = ModelContext(container)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        let workout = try XCTUnwrap(workouts.first)
        XCTAssertEqual(workouts.count, 1)
        XCTAssertEqual(workout.id, "w-1")
        XCTAssertEqual(workout.title, "Morning Workout")
        XCTAssertEqual(workout.workoutDescription, "Felt strong")
        XCTAssertEqual(workout.startTime, start)

        let exercise = try XCTUnwrap(workout.exercises.first)
        XCTAssertEqual(workout.exercises.count, 1)
        XCTAssertEqual(exercise.title, "Bench Press (Barbell)")
        XCTAssertEqual(exercise.templateID, "05293BCA")
        XCTAssertNil(exercise.supersetID)

        let sets = exercise.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.first?.type, .warmup)
        XCTAssertEqual(sets.first?.weightKg, 60)
        XCTAssertEqual(sets.last?.type, .normal)
        XCTAssertEqual(sets.last?.reps, 8)
        XCTAssertEqual(sets.last?.rpe, 9.5)
    }

    // MARK: - Replacement

    func testReplaceDropsWorkoutsMissingFromTheNewWindow() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(with: [
            ActivityFactory.activity(id: "w-1", start: start),
            ActivityFactory.activity(id: "w-2", start: start),
        ])

        // Second sync: the user deleted w-1 in Hevy.
        try await sut.replaceCachedWorkouts(with: [
            ActivityFactory.activity(id: "w-2", start: start),
        ])

        let ids = try await sut.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["w-2"])
    }

    func testReplaceDoesNotDuplicateAWorkoutSyncedTwice() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let activity = ActivityFactory.activity(id: "w-1", start: start)

        try await sut.replaceCachedWorkouts(with: [activity])
        try await sut.replaceCachedWorkouts(with: [activity])

        let count = try await sut.workoutCount()
        XCTAssertEqual(count, 1)
    }

    func testReplaceCascadeDeletesExercisesAndSets() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(with: [
            ActivityFactory.activity(id: "w-1", start: start),
        ])
        try await sut.replaceCachedWorkouts(with: [])

        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSet>()), 0)
    }

    func testCachedWorkoutIDsAreSortedNewestFirst() async throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(with: [
            ActivityFactory.activity(id: "older", start: old),
            ActivityFactory.activity(id: "newer", start: recent),
        ])

        let ids = try await sut.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["newer", "older"])
    }

    // MARK: - Deletion

    func testDeleteAllEmptiesTheCache() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(with: [
            ActivityFactory.activity(id: "w-1", start: start),
        ])

        try await sut.deleteAll()

        let count = try await sut.workoutCount()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Durability (#25 AC2)

    func testCachedWorkoutsSurviveAContainerRestart() async throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await Self.withDiskContainer(at: storeURL) { container in
            let store = WorkoutStore(modelContainer: container)
            try await store.replaceCachedWorkouts(with: [
                ActivityFactory.activity(id: "w-1", start: start),
            ])
        }

        // A second container on the same file stands in for the next launch
        // after an app kill.
        try await Self.withDiskContainer(at: storeURL) { container in
            let store = WorkoutStore(modelContainer: container)
            let ids = try await store.cachedWorkoutIDs()
            XCTAssertEqual(ids, ["w-1"])

            let context = ModelContext(container)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSet>()), 2)
        }
    }

    // MARK: - Helpers

    /// Runs `body` against a fresh on-disk container, released afterwards so
    /// the next call has to read from the file rather than from memory.
    private static func withDiskContainer(
        at url: URL,
        body: (ModelContainer) async throws -> Void
    ) async throws {
        let configuration = ModelConfiguration(
            schema: ModelContainerFactory.schema,
            url: url,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: configuration
        )
        try await body(container)
    }

}

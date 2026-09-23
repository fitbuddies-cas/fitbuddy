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
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
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
        XCTAssertEqual(workout.endTime, start.addingTimeInterval(3600))
        XCTAssertEqual(workout.updatedAt, start.addingTimeInterval(3600))

        let exercise = try XCTUnwrap(workout.exercises.first)
        XCTAssertEqual(workout.exercises.count, 1)
        XCTAssertEqual(exercise.title, "Bench Press (Barbell)")
        XCTAssertEqual(exercise.notes, "Paid attention to form")
        XCTAssertEqual(exercise.templateID, "05293BCA")
        // Every field asserted against its real value, `nil` for none of them:
        // the mapping is two hops long, and a field dropped anywhere along it
        // has to fail here rather than disappear from the detail view.
        XCTAssertEqual(exercise.supersetID, 1)

        let sets = exercise.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets.first?.type, .warmup)
        XCTAssertEqual(sets.first?.weightKg, 60)
        XCTAssertEqual(sets.last?.type, .normal)
        XCTAssertEqual(sets.last?.reps, 8)
        XCTAssertEqual(sets.last?.rpe, 9.5)
    }

    // MARK: - Kind & cardio (#180)

    /// US-15 / #180 AC2: a Hevy workout is cached as strength training with
    /// no cardio block — the defaults carry it, no mapping has to say so.
    /// The routine snapshot (#240) travels into the cache as it was taken:
    /// the id, the routine's timestamp at sync time, and a target per set.
    func testARoutineBackedActivityCachesItsTargetsAndSnapshot() async throws {
        let updatedAt = Date(timeIntervalSince1970: 1_749_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.routineActivity(
                id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000), routineUpdatedAt: updatedAt
            ),
        ])

        let context = ModelContext(container)
        let workout = try XCTUnwrap(try context.fetch(FetchDescriptor<Workout>()).first)
        XCTAssertEqual(workout.routineID, "r-1")
        XCTAssertEqual(workout.routineUpdatedAt, updatedAt)
        let sets = try XCTUnwrap(workout.exercises.first?.sets.sorted { $0.index < $1.index })
        XCTAssertEqual(sets.map(\.targetReps), [10, 12])
    }

    /// A re-sync rewrites the window, but the routine snapshot a session was
    /// first cached with survives it (#240): the connector hands over the
    /// routine as it stands today, and taking that would compare a past
    /// session against a plan that did not apply when it was trained.
    func testAReSyncKeepsTheRoutineSnapshotASessionWasFirstCachedWith() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let first = Date(timeIntervalSince1970: 1_749_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.routineActivity(id: "w-1", start: start, routineUpdatedAt: first),
        ])

        // The routine was edited since: new targets, a newer timestamp.
        var edited = ActivityFactory.routineActivity(id: "w-1", start: start, routineUpdatedAt: first.addingTimeInterval(86_400))
        edited.exercises[0].sets[0].targetReps = 6
        edited.exercises[0].sets[1].targetReps = 8
        let newer = ActivityFactory.routineActivity(id: "w-2", start: start.addingTimeInterval(86_400), routineUpdatedAt: first.addingTimeInterval(86_400))
        try await sut.replaceCachedWorkouts(from: .hevy, with: [edited, newer])

        let context = ModelContext(container)
        let workouts = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.id)]))
        XCTAssertEqual(workouts.map(\.routineUpdatedAt), [first, first.addingTimeInterval(86_400)])
        let cached = try XCTUnwrap(workouts.first?.exercises.first?.sets.sorted { $0.index < $1.index })
        XCTAssertEqual(cached.map(\.targetReps), [10, 12], "the first snapshot stays")
        let fresh = try XCTUnwrap(workouts.last?.exercises.first?.sets.sorted { $0.index < $1.index })
        XCTAssertEqual(fresh.map(\.targetReps), [10, 12], "a session cached for the first time takes the routine as it stands")
    }

    /// A session cached without a routine — synced before the routine was
    /// read, or before V6 — takes the snapshot the next sync brings: there is
    /// nothing older to keep.
    func testAReSyncFillsASnapshotTheCacheDidNotHave() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [ActivityFactory.activity(id: "w-1", start: start)])

        try await sut.replaceCachedWorkouts(from: .hevy, with: [ActivityFactory.routineActivity(id: "w-1", start: start)])

        let context = ModelContext(container)
        let workout = try XCTUnwrap(try context.fetch(FetchDescriptor<Workout>()).first)
        XCTAssertEqual(workout.routineID, "r-1")
        XCTAssertEqual(workout.exercises.first?.sets.sorted { $0.index < $1.index }.map(\.targetReps), [10, 12])
    }

    /// A freely logged session says so: no routine, no targets — a state the
    /// 2-for-2 rule reads as not checkable, and nothing invented in its place.
    func testAFreelyLoggedActivityCachesNoRoutineAndNoTargets() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000)),
        ])

        let context = ModelContext(container)
        let workout = try XCTUnwrap(try context.fetch(FetchDescriptor<Workout>()).first)
        XCTAssertNil(workout.routineID)
        XCTAssertNil(workout.routineUpdatedAt)
        XCTAssertEqual(workout.exercises.first?.sets.map(\.targetReps), [nil, nil])
    }

    func testAStrengthActivityCachesAsStrengthWithoutCardio() async throws {
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "w-1", start: Date(timeIntervalSince1970: 1_750_000_000)),
        ])

        let workout = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<Workout>()).first)
        XCTAssertEqual(workout.kind, .strength)
        XCTAssertNil(workout.cardio)
        XCTAssertNil(WorkoutSummary(workout: workout).cardio)
        XCTAssertEqual(WorkoutSummary(workout: workout).kind, .strength)
    }

    /// Every cardio field survives `Activity` → `Workout` → `WorkoutSummary`:
    /// the columns are flat, so one forgotten assignment would silently drop
    /// a metric on the way into the cache.
    func testACardioActivityCachesItsKindAndEveryMetric() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            ActivityFactory.cardioActivity(id: "strava:1", start: start),
        ])

        let workout = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<Workout>()).first)
        let cardio = try XCTUnwrap(workout.cardio)
        XCTAssertEqual(workout.kind, .run)
        XCTAssertEqual(cardio.averageHeartRate, 148)
        XCTAssertEqual(cardio.maxHeartRate, 172)
        XCTAssertEqual(cardio.elevationGainMeters, 412.5)
        XCTAssertEqual(cardio.averageSpeedMetersPerSecond, 2.78)
        XCTAssertEqual(cardio.energyKilojoules, 920)
        XCTAssertEqual(cardio.perceivedEffort, 64)
        XCTAssertEqual(cardio.activeCalories, 530)
        XCTAssertEqual(cardio.distanceMeters, 10_400)
        XCTAssertEqual(cardio.durationSeconds, 3742)
        XCTAssertEqual(cardio.trainingLoad, 143.22)

        let summary = WorkoutSummary(workout: workout)
        XCTAssertEqual(summary.kind, .run)
        XCTAssertEqual(summary.cardio, cardio)
        // The session logged no sets, so the dashboard's two figures come out
        // of the cardio block rather than out of an aggregation over nothing.
        XCTAssertEqual(summary.distanceMeters, 10_400)
        XCTAssertEqual(summary.durationSeconds, 3742)
        XCTAssertTrue(summary.isCardio)
    }

    /// A row written before V5 has no sport recorded. It must not read as
    /// strength training just because that is the newer default — a cached
    /// run would end up in the wrong domain of the analysis.
    func testASessionCachedBeforeV5ReadsItsKindFromItsSource() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            ActivityFactory.cardioActivity(id: "strava:1", start: start),
        ])
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "w-1", start: start),
        ])

        let context = ModelContext(container)
        let workouts = try context.fetch(FetchDescriptor<Workout>())
        for workout in workouts {
            workout.kindRawValue = nil
        }
        try context.save()

        let byID = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.kind) })
        XCTAssertEqual(byID["strava:1"], .other)
        XCTAssertEqual(byID["w-1"], .strength)
    }

    // MARK: - Replacement

    func testReplaceDropsWorkoutsMissingFromTheNewWindow() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "w-1", start: start),
            ActivityFactory.activity(id: "w-2", start: start),
        ])

        // Second sync: the user deleted w-1 in Hevy.
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "w-2", start: start),
        ])

        let ids = try await sut.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["w-2"])
    }

    func testReplaceDoesNotDuplicateAWorkoutSyncedTwice() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let activity = ActivityFactory.activity(id: "w-1", start: start)

        try await sut.replaceCachedWorkouts(from: .hevy, with: [activity])
        try await sut.replaceCachedWorkouts(from: .hevy, with: [activity])

        let count = try await sut.workoutCount()
        XCTAssertEqual(count, 1)
    }

    func testReplaceCascadeDeletesExercisesAndSets() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "w-1", start: start),
        ])
        try await sut.replaceCachedWorkouts(from: .hevy, with: [])

        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSet>()), 0)
    }

    func testCachedWorkoutIDsAreSortedNewestFirst() async throws {
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "older", start: old),
            ActivityFactory.activity(id: "newer", start: recent),
        ])

        let ids = try await sut.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["newer", "older"])
    }

    // MARK: - Deletion

    func testDeleteAllEmptiesTheCache() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "w-1", start: start),
        ])

        try await sut.deleteAll()

        let count = try await sut.workoutCount()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Per-source windows (#141)

    /// The reason `source` exists: a Hevy sync must not wipe the Strava
    /// sessions cached next to it, or the dashboard flickers between sources.
    func testReplacingOneSourceLeavesTheOtherSourceUntouched() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "hevy-1", start: start),
        ])
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            Activity(id: "strava:1", title: "Run", startTime: start, source: .strava),
        ])

        // Next Hevy sync, with a different window.
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "hevy-2", start: start),
        ])

        let ids = try await sut.cachedWorkoutIDs()
        XCTAssertEqual(Set(ids), ["hevy-2", "strava:1"])
        let hevyCount = try await sut.workoutCount(from: .hevy)
        let stravaCount = try await sut.workoutCount(from: .strava)
        XCTAssertEqual(hevyCount, 1)
        XCTAssertEqual(stravaCount, 1)
    }

    func testReplacingWithAnEmptyWindowClearsOnlyThatSource() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "hevy-1", start: start),
        ])
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            Activity(id: "strava:1", title: "Run", startTime: start, source: .strava),
        ])

        try await sut.replaceCachedWorkouts(from: .strava, with: [])

        let ids = try await sut.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["hevy-1"])
    }

    func testDeleteCachedWorkoutsFromOneSourceKeepsTheOther() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "hevy-1", start: start),
        ])
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            Activity(id: "strava:1", title: "Run", startTime: start, source: .strava),
        ])

        try await sut.deleteCachedWorkouts(from: .strava)

        let ids = try await sut.cachedWorkoutIDs()
        XCTAssertEqual(ids, ["hevy-1"])
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
    }

    func testSourceTravelsIntoTheSummaryAndTheDetail() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            Activity(id: "strava:1", title: "Run", startTime: start, source: .strava),
        ])

        let summaries = try await sut.workoutSummaries(since: .distantPast)
        let detail = try await sut.workoutDetail(id: "strava:1")
        XCTAssertEqual(summaries.map(\.source), [.strava])
        XCTAssertEqual(detail?.source, .strava)
    }

    func testDeleteAllClearsEverySource() async throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        try await sut.replaceCachedWorkouts(from: .hevy, with: [
            ActivityFactory.activity(id: "hevy-1", start: start),
        ])
        try await sut.replaceCachedWorkouts(from: .strava, with: [
            Activity(id: "strava:1", title: "Run", startTime: start, source: .strava),
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
            try await store.replaceCachedWorkouts(from: .hevy, with: [
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

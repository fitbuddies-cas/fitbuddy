import SwiftData
import XCTest
@testable import FitBuddy

/// Tests for `ModelContainerFactory`, in particular the ADR-001 hardening —
/// it is invisible at runtime and would otherwise regress unnoticed.
final class ModelContainerFactoryTests: XCTestCase {
    func testInMemoryContainerAcceptsTheWholeWorkoutHierarchy() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)

        context.insert(
            Workout(
                id: "w-1",
                title: "Morning Workout",
                startTime: Date(timeIntervalSince1970: 1_750_000_000),
                exercises: [Exercise(index: 0, title: "Squat (Barbell)", sets: [
                    ExerciseSet(index: 0, type: .normal, weightKg: 100, reps: 5),
                ])]
            )
        )
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSet>()), 1)
    }

    /// The migration #141 introduces and ADR-001 asked to rehearse: a store
    /// written by the build before #141 (schema V1, no `sourceRawValue`) has to
    /// open under the current schema with every workout and analysis intact,
    /// and every migrated workout has to read as Hevy — the only source that
    /// build knew. Since #192 this runs two stages in turn, V1 → V2 → V3.
    /// A fresh store would prove nothing; it never had a version to come from.
    func testV1StoreMigratesToTheCurrentSchemaWithEveryWorkoutReadingAsHevy() throws {
        let storeURL = try makeTemporaryStoreURL()

        // Written the way the shipped build wrote it: V1's models under a
        // plain, unversioned `Schema` and no migration plan. In a helper so
        // the old container is released before the new one opens the same
        // SQLite file — two live containers on one store is exactly what
        // `makeTemporaryStoreURL()` gives every test its own file to avoid.
        try writeV1Store(at: storeURL)

        // Reopened by this build. A schema change SwiftData cannot migrate
        // lightly — or a V1 it does not recognise — would throw right here.
        let container = try ModelContainerFactory.makePersistent(storeURL: storeURL)
        let context = ModelContext(container)

        let workouts = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.id)]))
        XCTAssertEqual(workouts.map(\.id), ["w-1", "w-2"])
        XCTAssertEqual(workouts.map(\.sourceRawValue), ["hevy", "hevy"])
        XCTAssertEqual(workouts.map(\.source), [.hevy, .hevy])
        // The tree under the workouts survived too, not just the rows.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseSet>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisResult>()), 1)

        // And the migrated store accepts what only V2 can write.
        let store = WorkoutStore(modelContainer: container)
        let expectation = expectation(description: "strava window cached")
        Task {
            try await store.replaceCachedWorkouts(from: .strava, with: [
                Activity(id: "strava:1", title: "Run", startTime: Date(timeIntervalSince1970: 1_760_000_000), source: .strava),
            ])
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 3)
    }

    /// The V2 → V3 stage of #192: a store written by the previous build
    /// (schema V2, no profile columns on `AnalysisResult`) has to open under
    /// V3 with the analysis and its source-tagged workouts intact, and every
    /// migrated analysis has to read as "no profile" — none of those runs had
    /// one. The first attempt at #192 changed V2 in place, and the store this
    /// test writes came back as "unknown model version" and fell back to an
    /// empty in-memory container; this is the test that would have caught it.
    func testV2StoreMigratesToV3WithEveryAnalysisReadingAsNoProfile() throws {
        let storeURL = try makeTemporaryStoreURL()
        try writeV2Store(at: storeURL)

        let container = try ModelContainerFactory.makePersistent(storeURL: storeURL)
        let context = ModelContext(container)

        let workouts = try context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.id)]))
        XCTAssertEqual(workouts.map(\.source), [.strava, .hevy])
        let analyses = try context.fetch(FetchDescriptor<AnalysisResult>())
        XCTAssertEqual(analyses.map(\.sessionCount), [12])
        XCTAssertEqual(analyses.map(\.goal), [nil])
        XCTAssertEqual(analyses.map(\.experience), [nil])

        // And the migrated store accepts what only V3 can write.
        let store = AnalysisResultStore(modelContainer: container)
        let expectation = expectation(description: "profiled analysis saved")
        Task {
            var analysed = AnalysisContext(sessionCount: 3, window: .default)
            analysed.profile = TrainingProfile(goal: .stayFit, experience: .oneToThreeYears)
            try await store.save(text: "Keep the routine.", generatedAt: Date(timeIntervalSince1970: 1_790_000_000), context: analysed)
            let latest = try await store.latest()
            XCTAssertEqual(latest?.context.profile, analysed.profile)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisResult>()), 2)
    }

    /// Writes a Strava and a Hevy workout and one analysis under
    /// `FitBuddySchemaV2`, exactly as the previous build would have, and lets
    /// the container go out of scope again.
    private func writeV2Store(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: FitBuddySchemaV2.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(
            FitBuddySchemaV2.Workout(
                id: "strava:1",
                title: "Run",
                startTime: Date(timeIntervalSince1970: 1_760_000_000),
                sourceRawValue: "strava"
            )
        )
        context.insert(
            FitBuddySchemaV2.Workout(id: "w-1", title: "Morning Workout", startTime: Date(timeIntervalSince1970: 1_750_000_000))
        )
        context.insert(
            FitBuddySchemaV2.AnalysisResult(
                text: "Add 2.5 kg on bench next session.",
                generatedAt: Date(timeIntervalSince1970: 1_788_000_000),
                windowWeeks: 4,
                sessionCount: 12
            )
        )
        try context.save()
    }

    /// Writes two workouts (one with a full tree) and one analysis under
    /// `FitBuddySchemaV1`, exactly as the previous build would have, and lets
    /// the container go out of scope again.
    private func writeV1Store(at storeURL: URL) throws {
        let schema = Schema(versionedSchema: FitBuddySchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(
            FitBuddySchemaV1.Workout(
                id: "w-1",
                title: "Morning Workout",
                startTime: Date(timeIntervalSince1970: 1_750_000_000),
                exercises: [
                    FitBuddySchemaV1.Exercise(index: 0, title: "Squat (Barbell)", sets: [
                        FitBuddySchemaV1.ExerciseSet(index: 0, typeRawValue: "normal", weightKg: 100, reps: 5),
                    ]),
                ]
            )
        )
        context.insert(
            FitBuddySchemaV1.Workout(id: "w-2", title: "Evening Workout", startTime: Date(timeIntervalSince1970: 1_750_100_000))
        )
        context.insert(
            FitBuddySchemaV1.AnalysisResult(
                text: "Add 2.5 kg on bench next session.",
                generatedAt: Date(timeIntervalSince1970: 1_788_000_000),
                windowWeeks: 4,
                sessionCount: 12
            )
        )
        try context.save()
    }

    func testPersistentStoreIsExcludedFromICloudBackup() throws {
        let container = try ModelContainerFactory.makePersistent(storeURL: try makeTemporaryStoreURL())
        let storeURL = try XCTUnwrap(container.configurations.first?.url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        // QA-1: health data must never reach an iCloud device backup.
        try assertExcludedFromBackup(storeURL)
        // Covers the -wal/-shm sidecars, which SQLite creates only on first write.
        try assertExcludedFromBackup(storeURL.deletingLastPathComponent())
    }

    // The second ADR-001 measure, `NSFileProtectionComplete`, is deliberately
    // not asserted here: the simulator runs on APFS and does not store a
    // protection class at all, so `attributesOfItem` reports nil whatever the
    // code asks for. Verifying it needs a device run (ADR-001, open point).

    /// A store of its own per test, not the default one: the tests run inside
    /// the FitBuddy host, which already holds the real store open — and a
    /// second container on the same SQLite file would also outlive the run.
    private func makeTemporaryStoreURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("default.store")
    }

    private func assertExcludedFromBackup(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "\(url.lastPathComponent)", file: file, line: line)
    }
}

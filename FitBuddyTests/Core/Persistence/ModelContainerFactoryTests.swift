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

    /// The one case the issue asks to verify (#97): `AnalysisResult` was added
    /// to an already-shipped schema, so an installed store has to open under
    /// the new one and keep its workouts. A fresh store would prove nothing —
    /// it never had an old version to migrate from.
    func testExistingStoreGainsTheAnalysisEntityWithoutLosingItsWorkouts() throws {
        let storeURL = try makeTemporaryStoreURL()
        let oldSchema = Schema([Workout.self, Exercise.self, ExerciseSet.self])

        // Written by a build that did not know `AnalysisResult`, in a helper so
        // the old container is released before the new one opens the same
        // SQLite file — two live containers on one store is exactly what
        // `makeTemporaryStoreURL()` gives every test its own file to avoid.
        try writeLegacyStore(at: storeURL, schema: oldSchema)

        // Reopened by this build. A schema change SwiftData cannot migrate
        // lightly would throw right here.
        let container = try ModelContainerFactory.makePersistent(storeURL: storeURL)
        let context = ModelContext(container)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Workout>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisResult>()), 0)

        context.insert(
            AnalysisResult(
                text: "Add 2.5 kg on bench next session.",
                generatedAt: Date(timeIntervalSince1970: 1_788_000_000),
                windowWeeks: 4,
                sessionCount: 12
            )
        )
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<AnalysisResult>()), 1)
    }

    /// Writes one workout under the pre-`AnalysisResult` schema and lets the
    /// container go out of scope again.
    private func writeLegacyStore(at storeURL: URL, schema: Schema) throws {
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        )
        let context = ModelContext(container)
        context.insert(
            Workout(id: "w-1", title: "Morning Workout", startTime: Date(timeIntervalSince1970: 1_750_000_000))
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

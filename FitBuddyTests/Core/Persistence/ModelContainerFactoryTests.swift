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

    func testPersistentStoreIsExcludedFromICloudBackup() throws {
        let container = try ModelContainerFactory.makePersistent()
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

    private func assertExcludedFromBackup(
        _ url: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "\(url.lastPathComponent)", file: file, line: line)
    }
}

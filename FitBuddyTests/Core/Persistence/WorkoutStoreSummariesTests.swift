import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for the dashboard's read path into the cache (issue #26), run
/// against a real in-memory SwiftData container.
final class WorkoutStoreSummariesTests: XCTestCase {
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

    func testReturnsOnlyWorkoutsInsideTheWindowNewestFirst() async throws {
        try insert([
            makeWorkout(id: "old", start: reference.addingTimeInterval(-100 * 86_400)),
            makeWorkout(id: "older-in-window", start: reference.addingTimeInterval(-40 * 86_400)),
            makeWorkout(id: "recent", start: reference.addingTimeInterval(-1 * 86_400)),
        ])

        let windowStart = TrainingWindow.start(endingAt: reference)
        let summaries = try await sut.workoutSummaries(since: windowStart)

        XCTAssertEqual(summaries.map(\.id), ["recent", "older-in-window"])
    }

    func testVolumeSumsWeightTimesRepsAndIgnoresWarmupSets() async throws {
        try insert([
            makeWorkout(id: "w-1", start: reference, sets: [
                (type: .warmup, weight: 60, reps: 10),   // excluded
                (type: .normal, weight: 100, reps: 8),   // 800
                (type: .normal, weight: 100, reps: 8),   // 800
                (type: .dropset, weight: 80, reps: 5),   // 400
            ]),
        ])

        let summaries = try await sut.workoutSummaries(since: .distantPast)
        let summary = try XCTUnwrap(summaries.first)

        XCTAssertEqual(summary.volumeKg, 2000, accuracy: 0.001)
        XCTAssertEqual(summary.countedSetCount, 3)
        XCTAssertEqual(summary.exerciseCount, 1)
    }

    func testSetsWithoutWeightOrRepsContributeNoVolume() async throws {
        try insert([
            makeWorkout(id: "cardio", start: reference, sets: [
                (type: .normal, weight: nil, reps: nil),
                (type: .normal, weight: nil, reps: 12),
                (type: .normal, weight: 40, reps: nil),
            ]),
        ])

        let summaries = try await sut.workoutSummaries(since: .distantPast)
        let summary = try XCTUnwrap(summaries.first)

        XCTAssertEqual(summary.volumeKg, 0)
        // The sets still count as performed — only their kg volume is unknown.
        XCTAssertEqual(summary.countedSetCount, 3)
    }

    func testEmptyCacheReturnsNoSummaries() async throws {
        let summaries = try await sut.workoutSummaries(since: .distantPast)
        XCTAssertTrue(summaries.isEmpty)
    }

    // MARK: - Helpers

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
        sets: [(type: SetType, weight: Double?, reps: Int?)] = [(.normal, 100, 10)]
    ) -> Workout {
        let exercise = Exercise(
            index: 0,
            title: "Bench Press (Barbell)",
            sets: sets.enumerated().map { index, set in
                ExerciseSet(index: index, type: set.type, weightKg: set.weight, reps: set.reps)
            }
        )
        return Workout(id: id, title: "Session", startTime: start, exercises: [exercise])
    }
}

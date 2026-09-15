import SwiftData
import XCTest
@testable import FitBuddy

/// Unit tests for the sync stub the UI tests run behind (#120, #150).
///
/// Small, but it is the only thing asserting *what* the dashboard sees on a
/// stubbed launch: the happy-path UI test only proves the dashboard appears,
/// not that it appears on the empty state rather than in a failure — and the
/// refresh UI test reads its verdict off a session count this stub produces.
final class StubWorkoutSyncTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

    /// Isolated `UserDefaults` suites handed to seeds, removed on tear-down.
    private var suiteNames: [String] = []

    override func tearDown() async throws {
        for suiteName in suiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        suiteNames = []
        try await super.tearDown()
    }

    func testReportsAnEmptyWindowAtTheInjectedTime() async throws {
        let sut = StubWorkoutSync(now: { self.reference })

        let result = try await sut.syncRecentWorkouts()

        // Zero workouts and no error: the dashboard lands on "no training
        // data", which is the honest picture for an account with nothing here.
        XCTAssertEqual(result.workoutCount, 0)
        XCTAssertEqual(result.syncedAt, reference)
        XCTAssertEqual(result.windowStart, TrainingWindow.start(endingAt: reference))
    }

    /// It reaches no network, so it can never fail — a stub that threw would
    /// put the dashboard into the offline banner instead of the empty state.
    func testNeverFails() async throws {
        let sut = StubWorkoutSync(now: { self.reference })

        for _ in 0..<3 {
            _ = try await sut.syncRecentWorkouts()
        }
    }

    // MARK: - Seeded launches (#150)

    /// The seeded stub stands in for a real sync, so the timestamp has to move
    /// with the cache: left at `nil`, the status strip would report the seeded
    /// window as never synced and put a warning over a full dashboard (US-8).
    func testSeededSyncCachesTheWindowAndRecordsTheTimestamp() async throws {
        let seed = try makeSeed(activities: [activity("a-1"), activity("a-2")])
        let sut = StubWorkoutSync(now: { self.reference }, seed: seed)

        let result = try await sut.syncRecentWorkouts()

        XCTAssertEqual(result.workoutCount, 2)
        let cached = try await seed.store.workoutCount()
        XCTAssertEqual(cached, 2)
        let stored = await seed.timestamps.lastSync()
        XCTAssertEqual(stored, reference)
    }

    /// One more session per completed sync, so the UI test can read off the
    /// screen whether a pull-to-refresh landed.
    func testEveryCompletedSyncAfterTheFirstAddsOneSession() async throws {
        let seed = try makeSeed(activities: [activity("a-1")])
        let sut = StubWorkoutSync(now: { self.reference }, seed: seed)

        _ = try await sut.syncRecentWorkouts()
        let second = try await sut.syncRecentWorkouts()

        XCTAssertEqual(second.workoutCount, 2)
        let cached = try await seed.store.workoutCount()
        XCTAssertEqual(cached, 2)
    }

    /// A sync cancelled while it sleeps — the launch sync displaced by a pull
    /// — never writes and must not use up a number, or the next completed sync
    /// would show one session too many for the UI test's literal expectation.
    func testADisplacedSyncDoesNotCountAsASession() async throws {
        let seed = try makeSeed(activities: [activity("a-1")])
        let sut = StubWorkoutSync(now: { self.reference }, delay: .milliseconds(20), seed: seed)

        let displaced = Task { try await sut.syncRecentWorkouts() }
        displaced.cancel()
        do {
            _ = try await displaced.value
            XCTFail("Expected the sleep to throw the cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError, "Unexpected error: \(error)")
        }
        let landed = try await sut.syncRecentWorkouts()

        XCTAssertEqual(landed.workoutCount, 1, "A sync that never wrote must not add a session")
    }

    // MARK: - Helpers

    private func makeSeed(activities: [Activity]) throws -> StubWorkoutSync.Seed {
        let suiteName = "fitbuddy.tests.\(UUID().uuidString)"
        suiteNames.append(suiteName)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return StubWorkoutSync.Seed(
            store: WorkoutStore(modelContainer: try ModelContainerFactory.makeInMemory()),
            timestamps: SyncTimestampStore(defaults: defaults),
            activities: activities
        )
    }

    private func activity(_ id: String) -> Activity {
        Activity(id: id, title: "Session", startTime: reference.addingTimeInterval(-3_600))
    }
}

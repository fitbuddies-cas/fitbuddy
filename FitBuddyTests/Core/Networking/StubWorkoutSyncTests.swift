import XCTest
@testable import FitBuddy

/// Unit tests for the sync stub the UI tests run behind (#120).
///
/// Small, but it is the only thing asserting *what* the dashboard sees on a
/// stubbed launch: the happy-path UI test only proves the dashboard appears,
/// not that it appears on the empty state rather than in a failure.
final class StubWorkoutSyncTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_750_000_000)

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
}

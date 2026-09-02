import XCTest
@testable import FitBuddy

/// `hasWorkouts` gates the analysis entry point on the dashboard (#32): a false
/// positive offers an analysis with nothing to analyse, a false negative hides
/// the feature from a user who has trained.
final class WorkoutListStateTests: XCTestCase {
    func testLoadedWithWorkoutsHasWorkouts() {
        let workouts = [summary]
        let state = WorkoutListState.loaded(
            workouts: workouts,
            metrics: DashboardMetrics(summaries: workouts)
        )

        XCTAssertTrue(state.hasWorkouts)
    }

    /// `.loaded` with an empty array is reachable — the view model builds the
    /// state before it knows the window is empty — and must not offer an
    /// analysis.
    func testLoadedWithoutWorkoutsHasNone() {
        let state = WorkoutListState.loaded(workouts: [], metrics: DashboardMetrics(summaries: []))

        XCTAssertFalse(state.hasWorkouts)
    }

    func testNonLoadedStatesHaveNoWorkouts() {
        for state in [WorkoutListState.loading, .empty, .failed] {
            XCTAssertFalse(state.hasWorkouts, "\(state) must not offer an analysis")
        }
    }

    private var summary: WorkoutSummary {
        WorkoutSummary(
            id: "1",
            title: "Push day",
            startTime: Date(timeIntervalSince1970: 1_750_000_000),
            volumeKg: 4_200,
            exerciseCount: 4,
            countedSetCount: 12
        )
    }
}

import Foundation

/// UI state of the dashboard's workout list (US-2).
enum WorkoutListState: Equatable {
    /// First read of the cache has not finished yet.
    case loading
    /// The cache holds workouts inside the 90-day window.
    case loaded(workouts: [WorkoutSummary], metrics: DashboardMetrics)
    /// No workouts in the window — the «No training data for the last 90 days»
    /// case (US-2 AC3). Reached both by a new user and by one who paused
    /// training; the dashboard cannot tell the two apart, and neither should.
    case empty
    /// The local cache could not be read. Distinct from `.empty`: showing "no
    /// training data" for a broken store would tell the user something false
    /// about their training.
    case failed

    /// Whether the window holds training data to work with — what the analysis
    /// entry point needs before it is worth offering (#32).
    ///
    /// This is exactly the analysis guard's own condition (#87): the widest
    /// rung of `AnalysisWindow.ladder` spans `TrainingWindow.spanDays`, so a
    /// dashboard holding any workout at all is a dashboard whose analysis can
    /// run. The button therefore never leads into a dead end — a gap in the
    /// last four weeks widens the window instead of failing the run.
    var hasWorkouts: Bool {
        switch self {
        case .loaded(let workouts, _):
            return !workouts.isEmpty
        case .loading, .empty, .failed:
            return false
        }
    }
}

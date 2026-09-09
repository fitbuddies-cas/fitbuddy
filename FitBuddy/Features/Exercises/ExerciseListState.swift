import Foundation

/// UI state of the exercise list (US-7, #37).
enum ExerciseListState: Equatable {
    /// The first cache read has not finished yet.
    case loading
    /// The window holds movements, rolled up per exercise.
    case loaded([ExerciseSummary])
    /// The window holds no workouts at all — nothing has been trained in the
    /// last 90 days, or the cache was never filled. Distinct from a search
    /// that matches nothing: that one is about the query, this one about the
    /// data behind it.
    case empty
    /// The local cache could not be read. Kept apart from `.empty` for the
    /// reason the dashboard keeps them apart: "you have no exercises" and
    /// "your data could not be read" are different statements.
    case failed
}

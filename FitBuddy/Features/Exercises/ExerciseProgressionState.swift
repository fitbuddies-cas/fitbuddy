import Foundation

/// UI state of the exercise progression screen (US-9, #42).
enum ExerciseProgressionState: Equatable {
    /// The first cache read has not finished yet.
    case loading
    /// Enough sessions to draw a line between (AC1).
    case loaded(ExerciseProgression)
    /// The movement is in the window, but fewer than two sessions carry weight
    /// and reps — AC3's case. Kept apart from `.unavailable` because "you have
    /// not done this often enough yet" and "this is no longer in your window"
    /// ask the user for different things.
    case insufficientData(ExerciseProgression)
    /// The movement is not in the cached window at all. Reachable when the
    /// cache is replaced while the screen is open — a new Hevy key drops the
    /// window under it (#91).
    case unavailable
    /// The local cache could not be read. Distinct from every case above for
    /// the reason the dashboard keeps them apart: "no data" and "your data
    /// could not be read" are different statements.
    case failed
}

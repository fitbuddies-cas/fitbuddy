import Foundation

/// Read access to the cached window, rolled up per movement (US-7, #37).
///
/// Separate from `WorkoutSummaryReading` for the reason `WorkoutDetailReading`
/// is separate too: the exercise list needs a different projection of the same
/// cache, and a screen should depend on the read it makes, not on every read
/// `WorkoutStore` offers.
protocol ExerciseSummaryReading: Sendable {
    /// Movements performed in workouts that started at or after `date`, most
    /// recently performed first.
    func exerciseSummaries(since date: Date) async throws -> [ExerciseSummary]
}

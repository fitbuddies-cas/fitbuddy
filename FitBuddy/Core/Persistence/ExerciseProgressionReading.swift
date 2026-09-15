import Foundation

/// Read access to one movement's estimated 1RM over the cached window
/// (US-9, #41).
///
/// Its own protocol for the reason `ExerciseSummaryReading` is its own: the
/// progression screen needs a different projection of the same cache, and a
/// screen should depend on the read it makes rather than on everything
/// `WorkoutStore` can do.
protocol ExerciseProgressionReading: Sendable {
    /// The progression of the movement identified by `id` across workouts that
    /// started at or after `date`.
    ///
    /// - Parameter id: `ExerciseSummary.key(templateID:title:)` — the same
    ///   identity the exercise list hands out, so a row and its detail screen
    ///   are guaranteed to be about the same movement.
    /// - Returns: `nil` when the window holds no session with this movement at
    ///   all. An empty `points` array means the opposite: it was trained, but
    ///   never with weight and reps — a bodyweight movement has no curve, and
    ///   that is a different statement from "never trained".
    func exerciseProgression(id: String, since date: Date) async throws -> ExerciseProgression?
}

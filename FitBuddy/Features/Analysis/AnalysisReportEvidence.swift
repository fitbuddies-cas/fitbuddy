import Foundation

/// What the cache says about the analysed window — the facts
/// `AnalysisReportValidator` checks a report's cards against (#175).
///
/// Gathered by the caller, so the validator itself stays pure and
/// synchronous.
struct AnalysisReportEvidence: Equatable, Sendable {
    /// The exercises the prompt listed, with the working set each line named.
    let exercises: [ListedExercise]
    /// Sessions per week per muscle group in the analysed window, at the
    /// precision the prompt states them. A group missing here was not trained.
    let muscleGroupsPerWeek: [MuscleGroup: Double]
    /// The last seven days.
    let recovery: RecoveryMetrics
}

extension AnalysisReportEvidence {
    /// Gathers the evidence from the same reads the prompt was built from.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order — the read the prompt was
    ///     built from. Endurance sessions and sessions outside the window are
    ///     ignored, as in the prompt.
    ///   - exercises: The movements of the analysed window, as passed to
    ///     `AnalysisPromptBuilder.make`.
    ///   - progressions: The progressions passed to `AnalysisPromptBuilder.make`.
    ///   - details: Full workouts of the last seven days, for the mean RPE —
    ///     see `RecoveryMetrics.lastSevenDaysSessions(in:now:calendar:)`.
    ///   - window: The window analysed.
    ///   - now: The reference the prompt was built with.
    ///   - calendar: Decides where a day starts.
    init(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        details: [WorkoutDetail],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.init(
            exercises: AnalysisPromptBuilder.listedExercises(
                exercises: exercises,
                progressions: progressions,
                window: window,
                now: now,
                calendar: calendar
            ),
            muscleGroupsPerWeek: MuscleGroupFrequency.sessionsPerWeek(
                in: AnalysisPromptBuilder.analysedSessions(
                    in: summaries,
                    window: window,
                    now: now,
                    calendar: calendar
                ),
                window: window
            ),
            recovery: RecoveryMetrics(summaries: summaries, details: details, now: now, calendar: calendar)
        )
    }
}

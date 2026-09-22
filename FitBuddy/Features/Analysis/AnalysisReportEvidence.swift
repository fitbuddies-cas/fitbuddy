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
    /// The last seven days, across every source and both domains (#184).
    let recovery: RecoveryMetrics
    /// The profile this run was made under (US-15 AC1, #185).
    ///
    /// The validator needs it because two of its rules are about strength and
    /// nothing else: a progression card is a load increase on a listed
    /// exercise, and the `progress → hold` rewrite of #177 reads the absence
    /// of one as "the cards do not back the verdict". Under a profile that
    /// does not cover strength there are no listed exercises and a progression
    /// card is impossible by construction, so that absence is evidence of
    /// nothing — and rewriting the verdict would put "Hold steady this week."
    /// over the model's own argument for progressing an endurance block.
    ///
    /// Defaults to `.overallLoad`, which covers everything and therefore
    /// leaves every rule exactly as #175/#177 wrote it.
    var analysisProfile: AnalysisProfile = .overallLoad
    /// Whether the recovery week holds training this analysis did not cover.
    ///
    /// Not the same question as "is the profile single-domain": a Hevy-only
    /// window resolves to "Strength" and has left nothing out (#185). Only
    /// where both are true does the recovery card count sessions the rest of
    /// the screen says nothing about, and only then does its reasoning have to
    /// say so.
    var recoveryCountsUnanalysedTraining = false
}

extension AnalysisReportEvidence {
    /// Gathers the evidence from the same reads the prompt was built from.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order — the read the prompt was
    ///     built from. Sessions outside the window are ignored. The
    ///     muscle-group frequency reads the strength sessions only, which is
    ///     what a muscle group is a property of; the recovery metrics read
    ///     every session of the last seven days, strength and endurance
    ///     together (#184).
    ///   - exercises: The movements of the analysed window, as passed to
    ///     `AnalysisPromptBuilder.make`.
    ///   - progressions: The progressions passed to `AnalysisPromptBuilder.make`.
    ///   - details: Full workouts of the last seven days, for the mean RPE —
    ///     see `RecoveryMetrics.lastSevenDaysStrengthSessions(in:now:calendar:)`.
    ///     Handing over the endurance ones as well changes nothing.
    ///   - window: The window analysed.
    ///   - now: The reference the prompt was built with.
    ///   - calendar: Decides where a day starts.
    ///   - analysisProfile: The profile the run was made under (#185). The
    ///     default covers both domains, i.e. the behaviour of every build
    ///     before the choice existed.
    init(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        details: [WorkoutDetail],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current,
        analysisProfile: AnalysisProfile = .overallLoad
    ) {
        let unanalysed = RecoveryMetrics
            .lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
            .contains { !analysisProfile.covers(AnalysisDomain(summary: $0)) }
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
            recovery: RecoveryMetrics(summaries: summaries, details: details, now: now, calendar: calendar),
            analysisProfile: analysisProfile,
            recoveryCountsUnanalysedTraining: unanalysed
        )
    }
}

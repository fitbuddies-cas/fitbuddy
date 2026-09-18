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
    /// Since #186 it decides one more thing: which units a card may state its
    /// figures in. No kilograms under "Endurance", no kilometres under
    /// "Strength" (US-15 AC5) — see `MetricUnit.domain`.
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
    /// How strength and endurance sat in the same seven days — what an
    /// interference card is checked against and built from (#186).
    ///
    /// An empty week by default, i.e. "no interference to write about", so a
    /// fixture that predates #186 turns such a card into a note rather than
    /// validating it against figures nobody counted.
    var interference = InterferenceMetrics(strengthDays: 0, cardioDays: 0, overlapDays: 0)
    /// The app's own figure for each unit a metric card can be stated in, over
    /// the last seven days (#186). A unit missing here has no figure to check
    /// a card against, and a card in it is not validated.
    var weeklyMetrics: [MetricUnit: Double] = [:]
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
    ///   - analysisProfile: The profile the run was made under (#185, #186).
    ///     The default covers both domains, i.e. the behaviour of every build
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
        let recovery = RecoveryMetrics(summaries: summaries, details: details, now: now, calendar: calendar)
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
            recovery: recovery,
            analysisProfile: analysisProfile,
            recoveryCountsUnanalysedTraining: unanalysed,
            interference: InterferenceMetrics.metrics(in: summaries, now: now, calendar: calendar),
            weeklyMetrics: Self.weeklyMetrics(in: summaries, recovery: recovery, now: now, calendar: calendar)
        )
    }

    /// The app's figure for each unit, over the last seven days — the
    /// "Wochenaggregat" a metric card's `from` is checked against (#186).
    ///
    /// One rule for all five: **the week, whatever filled it.** No domain
    /// filter, because the units already carry the distinction that matters —
    /// only a strength session has volume in kilograms, only an endurance one
    /// covers a distance, and a heart rate and a duration belong to both. A
    /// filter would add a second place where "what counts as endurance" is
    /// decided, which is exactly what ADR-012 settled once.
    ///
    /// A unit whose figure is zero, or which nothing in the week recorded, is
    /// **absent** rather than present as `0`: a card cannot be checked against
    /// a figure that does not exist, and the validator turns it into a note
    /// instead of drawing a step from nowhere (US-15 AC7).
    ///
    /// The pace is the week's total distance over its total time, taken only
    /// over the sessions that recorded both — the same rule
    /// `EndurancePromptSection` settled on after its review, for the same
    /// reason: dividing a total that includes a treadmill session with no
    /// distance by a total that includes its time is not a pace anybody ran.
    static func weeklyMetrics(
        in summaries: [WorkoutSummary],
        recovery: RecoveryMetrics,
        now: Date,
        calendar: Calendar = .current
    ) -> [MetricUnit: Double] {
        let week = RecoveryMetrics.lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
        var metrics: [MetricUnit: Double] = [:]

        let volume = week.reduce(0) { $0 + $1.volumeKg }
        if volume > 0 { metrics[.kilograms] = volume }

        let meters = week.compactMap(\.distanceMeters).reduce(0, +)
        if meters > 0 { metrics[.kilometers] = meters / 1_000 }

        let seconds = week.compactMap(\.durationSeconds).reduce(0, +)
        if seconds > 0 { metrics[.hours] = Double(seconds) / 3_600 }

        if let heartRate = recovery.averageHeartRate, heartRate > 0 {
            metrics[.beatsPerMinute] = Double(heartRate)
        }

        let paced = week.filter { ($0.distanceMeters ?? 0) > 0 && ($0.durationSeconds ?? 0) > 0 }
        let pacedMeters = paced.compactMap(\.distanceMeters).reduce(0, +)
        let pacedSeconds = paced.compactMap(\.durationSeconds).reduce(0, +)
        if pacedMeters > 0, pacedSeconds > 0 {
            metrics[.minutesPerKilometer] = (Double(pacedSeconds) / 60) / (pacedMeters / 1_000)
        }

        return metrics
    }
}

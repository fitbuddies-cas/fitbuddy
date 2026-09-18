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
    /// How strength and endurance sat in the same seven days — what an
    /// interference card is checked against and built from (#186).
    let interference: InterferenceMetrics
    /// The app's own figure for each unit a metric card can be stated in, over
    /// the last seven days (#186). A unit missing here has no figure to check
    /// a card against, and a card in it is not validated.
    let weeklyMetrics: [MetricUnit: Double]
    /// What the user asked this analysis to be about (#185). Decides which
    /// units a card may be stated in: no kilograms under "Endurance", no
    /// kilometres under "Strength" (US-15 AC5).
    let analysisProfile: AnalysisProfile

    /// The three new members default to "nothing to check against, everything
    /// covered", so a caller that predates #186 — a fixture, a preview —
    /// compiles and validates exactly as it did.
    init(
        exercises: [ListedExercise],
        muscleGroupsPerWeek: [MuscleGroup: Double],
        recovery: RecoveryMetrics,
        interference: InterferenceMetrics = InterferenceMetrics(strengthDays: 0, cardioDays: 0, overlapDays: 0),
        weeklyMetrics: [MetricUnit: Double] = [:],
        analysisProfile: AnalysisProfile = .overallLoad
    ) {
        self.exercises = exercises
        self.muscleGroupsPerWeek = muscleGroupsPerWeek
        self.recovery = recovery
        self.interference = interference
        self.weeklyMetrics = weeklyMetrics
        self.analysisProfile = analysisProfile
    }
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
    ///   - analysisProfile: What the analysis was asked to be about (#185, #186).
    ///   - calendar: Decides where a day starts.
    init(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        details: [WorkoutDetail],
        window: AnalysisWindow,
        now: Date,
        analysisProfile: AnalysisProfile = .overallLoad,
        calendar: Calendar = .current
    ) {
        let recovery = RecoveryMetrics(summaries: summaries, details: details, now: now, calendar: calendar)
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
            interference: InterferenceMetrics.metrics(in: summaries, now: now, calendar: calendar),
            weeklyMetrics: Self.weeklyMetrics(in: summaries, recovery: recovery, now: now, calendar: calendar),
            analysisProfile: analysisProfile
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

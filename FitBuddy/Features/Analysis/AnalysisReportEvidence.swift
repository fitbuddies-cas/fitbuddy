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
    /// Sessions of the resolved window that this run analyses, i.e. those in
    /// the domains the profile covers — ADR-013 stage 1, first condition.
    ///
    /// Not `AnalysisContext`'s count, which is the honest total of everything
    /// the app read; this one is what the model was shown. Zero by default, so
    /// a fixture that predates #227 states no data basis rather than a
    /// borrowed one.
    var sessionsInWindow = 0
    /// Of those, the ones in the last seven days — ADR-013 stage 1, second
    /// condition.
    ///
    /// Separate from `recovery.sessions`, which counts every domain because a
    /// rest day is domain-blind (#184). This count is not: a week of nothing
    /// but runs leaves a strength analysis describing a pause, and the rule
    /// has to be able to say so.
    var sessionsInLastSevenDays = 0
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
    ///   - promptDetail: The rung the prompt was built at (#187). Only the
    ///     exercise list is affected: it is the one piece of evidence a
    ///     shortened prompt would otherwise leave the validator holding more
    ///     of than the model ever saw. Every other figure here is an aggregate
    ///     the ladder does not touch.
    init(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        details: [WorkoutDetail],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current,
        analysisProfile: AnalysisProfile = .overallLoad,
        promptDetail: AnalysisPromptDetail = .full
    ) {
        let recovery = RecoveryMetrics(summaries: summaries, details: details, now: now, calendar: calendar)
        let start = window.start(endingAt: now, calendar: calendar)
        let analysed = summaries.filter {
            $0.startTime >= start && analysisProfile.covers(AnalysisDomain(summary: $0))
        }
        let analysedWeek = RecoveryMetrics
            .lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
            .filter { analysisProfile.covers(AnalysisDomain(summary: $0)) }
        let unanalysed = RecoveryMetrics
            .lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
            .contains { !analysisProfile.covers(AnalysisDomain(summary: $0)) }
        self.init(
            exercises: AnalysisPromptBuilder.listedExercises(
                exercises: exercises,
                progressions: progressions,
                window: window,
                now: now,
                calendar: calendar,
                detail: promptDetail
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
            weeklyMetrics: Self.weeklyMetrics(
                in: summaries,
                now: now,
                calendar: calendar,
                analysisProfile: analysisProfile
            ),
            sessionsInWindow: analysed.count,
            sessionsInLastSevenDays: analysedWeek.count
        )
    }

    /// The app's figure for each unit, over the last seven days — the weekly
    /// aggregate a metric card's `from` is checked against (#186).
    ///
    /// **Only over the sessions the profile covers.** An anchor is what a card
    /// states as a measurement, so it may only come from training this
    /// analysis actually looked at: under "Strength" a `Weekly training time`
    /// card must not be anchored on hours that came from the runs the same
    /// screen says were left out. The recovery card is allowed to count them
    /// because it says so in its own reasoning (#185); a metric card has no
    /// such sentence and would simply print the figure.
    ///
    /// A unit whose figure is zero, or which nothing in the covered week
    /// recorded, is **absent** rather than present as `0`: a card cannot be
    /// checked against a figure that does not exist, and the validator turns
    /// it into a note instead of drawing a step from nowhere (US-15 AC7).
    ///
    /// What each unit means, precisely:
    ///
    /// - `kilograms` — Σ `volumeKg` of the covered sessions. Only a strength
    ///   session has any, so under "Endurance" this is absent.
    /// - `kilometers` — Σ `distanceMeters`. A strength session has one only
    ///   where its sets logged a distance.
    /// - `hours` — Σ `durationSeconds`, which is **the time the sessions
    ///   recorded, not the time they lasted**: `WorkoutSummary.durationSeconds`
    ///   is the sum over the counted sets for a Hevy session and the session
    ///   time for a source that reports whole sessions. An ordinary barbell
    ///   session logs no set duration and contributes nothing, so under
    ///   "Strength" over a Hevy cache this is usually absent — which is the
    ///   honest reading, not a gap: the app has no session length there.
    /// - `beatsPerMinute` — the mean over the covered sessions that recorded
    ///   one, by `RecoveryMetrics.meanHeartRate(in:)`. Kept although no model
    ///   card may use the unit (`MetricUnit.isStatableByTheModel`), because it
    ///   is a figure the app itself computes and a card the app builds from it
    ///   breaks no ground rule.
    /// - `minutesPerKilometer` — see below.
    ///
    /// The pace is the covered week's distance over its time, taken over the
    /// sessions that recorded **both** and whose sport is read in minutes per
    /// kilometre (`ActivityKind.isPacedPerKilometer`). Both restrictions come
    /// from `EndurancePromptSection.meanSpeed`, which settled them for the
    /// prompt: a treadmill session with no distance would otherwise divide a
    /// total that excludes its kilometres by a total that includes its
    /// minutes, and a ride is read in km/h — one run at 5:00 next to one ride
    /// at 30 km/h averages to 2:45 /km, a pace neither of them ran and one no
    /// card should either reject a real pace against or print.
    static func weeklyMetrics(
        in summaries: [WorkoutSummary],
        now: Date,
        calendar: Calendar = .current,
        analysisProfile: AnalysisProfile = .overallLoad
    ) -> [MetricUnit: Double] {
        let week = RecoveryMetrics
            .lastSevenDaysSessions(in: summaries, now: now, calendar: calendar)
            .filter { analysisProfile.covers(AnalysisDomain(summary: $0)) }
        var metrics: [MetricUnit: Double] = [:]

        let volume = week.reduce(0) { $0 + $1.volumeKg }
        if volume > 0 { metrics[.kilograms] = volume }

        let meters = week.compactMap(\.distanceMeters).reduce(0, +)
        if meters > 0 { metrics[.kilometers] = meters / 1_000 }

        let seconds = week.compactMap(\.durationSeconds).reduce(0, +)
        if seconds > 0 { metrics[.hours] = Double(seconds) / 3_600 }

        if let heartRate = RecoveryMetrics.meanHeartRate(in: week) {
            metrics[.beatsPerMinute] = Double(heartRate)
        }

        let paced = week.filter {
            $0.kind.isPacedPerKilometer
                && ($0.distanceMeters ?? 0) > 0
                && ($0.durationSeconds ?? 0) > 0
        }
        let pacedMeters = paced.compactMap(\.distanceMeters).reduce(0, +)
        let pacedSeconds = paced.compactMap(\.durationSeconds).reduce(0, +)
        if pacedMeters > 0, pacedSeconds > 0 {
            metrics[.minutesPerKilometer] = (Double(pacedSeconds) / 60) / (pacedMeters / 1_000)
        }

        return metrics
    }
}

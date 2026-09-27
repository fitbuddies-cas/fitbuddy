import Foundation

/// The strength half of the prompt: window totals, volume per week, muscle
/// groups, the comparison window, the session list and the Exercises section
/// (#30, #173, sectioned in #183).
///
/// Lifted out of `AnalysisPromptBuilder` unchanged, byte for byte: a cache
/// holding nothing but Hevy sessions has to produce exactly the prompt it
/// produced before the split (issue #183, AC1), and the cheapest way to
/// guarantee that is to move the code rather than rewrite it.
///
/// Which sessions reach it is what did change. `AnalysisPromptBuilder` now
/// selects them by `AnalysisDomain`, i.e. by the normalized sport (ADR-012),
/// so a Strava `WeightTraining` session is described here and a Hevy treadmill
/// session is not — where before the filter read the source and got both
/// backwards.
enum StrengthPromptSection {
    /// The strength sections, in prompt order. Empty when the window holds no
    /// strength session, which is what keeps the "Endurance" profile free of
    /// kg lines (#183 AC3).
    ///
    /// - Parameters:
    ///   - recent: Strength sessions of the analysed window.
    ///   - previous: Strength sessions of the equally long window before it.
    ///   - exercises: The movements of the analysed window, rolled up.
    ///   - progressions: The progression of each listed movement.
    ///   - detail: How long the lists may be (#187). The window totals, the
    ///     muscle split and the comparison window are the same at every rung —
    ///     only the three lists get shorter, and each says so.
    static func sections(
        recent: [WorkoutSummary],
        previous: [WorkoutSummary],
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        window: AnalysisWindow,
        recentStart: Date,
        previousStart: Date,
        now: Date,
        calendar: Calendar,
        days: PromptDayFormatter,
        detail: AnalysisPromptDetail = .full
    ) -> [String] {
        guard !recent.isEmpty else { return [] }
        return [
            windowSection(recent, window: window, from: recentStart, to: now, calendar: calendar, days: days),
            weeklySection(recent, window: window, now: now, calendar: calendar, days: days, detail: detail),
            muscleSection(recent, window: window),
            comparisonSection(
                previous,
                window: window,
                from: previousStart,
                to: recentStart,
                calendar: calendar,
                days: days
            ),
            sessionSection(recent, days: days, detail: detail),
            exerciseSection(
                exercises,
                progressions: progressions,
                window: window,
                from: recentStart,
                days: days,
                detail: detail
            ),
        ]
    }

    private static func windowSection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String {
        let days = PromptFigures.trainingDays(summaries, calendar: calendar)
        var lines = [
            "## Last \(window.weeks) weeks (\(formatter.string(start)) to \(formatter.string(end)))",
            "Sessions: \(summaries.count)",
            "Training days: \(days) (\(PromptFigures.frequency(days, window: window)) per week)",
            "Total volume: \(PromptFigures.kg(PromptFigures.volume(of: summaries)))",
        ]
        // Said next to the total it is missing from, not only in the session
        // list: a strength session a source recorded without sets contributes
        // nothing to the volume, and an unexplained gap between the session
        // count and the volume reads as a light week (#183).
        let setless = setlessSessions(summaries)
        if !setless.isEmpty {
            lines.append(
                "Of these, \(CountFormatter.labelled(setless.count, singular: "session")) "
                    + "logged no sets — their source records whole sessions, so their load is "
                    + "not in the volume above."
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Strength sessions whose source records whole efforts rather than sets.
    ///
    /// A Strava `WeightTraining` session is strength work — that is the point
    /// of the #183 flip — but it arrives as one synthetic exercise with a
    /// single cardio set and no weights at all. Rendered like a Hevy session
    /// it would claim sets that were never logged and a 0 kg total that rule 5
    /// invites the model to explain as bodyweight work.
    ///
    /// The source is the right test here, not the volume: `WorkoutSummary`
    /// already blanks the muscle split for these sources for the same reason,
    /// while a Hevy session at 0 kg is genuine bodyweight or timed work with
    /// real sets behind it.
    private static func setlessSessions(_ summaries: [WorkoutSummary]) -> [WorkoutSummary] {
        summaries.filter(\.source.isEnduranceSource)
    }

    /// Per-week figures, newest first. The totals alone cannot show whether
    /// the window's training was spread evenly or crammed into one week — and
    /// that difference changes the recommendation.
    private static func weeklySection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar,
        days: PromptDayFormatter,
        detail: AnalysisPromptDetail = .full
    ) -> String {
        // Bucketed once: the rung asks which weeks recorded anything before it
        // decides which of them to print (#187).
        let buckets = PromptFigures.weeks(summaries, window: window, now: now, calendar: calendar)
        let rows = detail.weekRows(in: window) { buckets[$0].sessions.isEmpty }
        let weeks = rows.indices.map { index -> String in
            let bucket = buckets[index]
            let label = index == 0 ? "most recent" : "\(index + 1) weeks back"
            return "- Week starting \(days.string(bucket.start)) (\(label)): "
                + "\(bucket.sessions.count) sessions, "
                + "\(PromptFigures.kg(PromptFigures.volume(of: bucket.sessions)))"
        }
        return (["## Volume per week"] + weeks + [rows.footer].compactMap { $0 }).joined(separator: "\n")
    }

    /// Volume, sets and training frequency per group. The frequency is the
    /// figure an imbalance card has to quote (#175), so it comes from
    /// `MuscleGroupFrequency`, which the validator reads as well.
    private static func muscleSection(_ summaries: [WorkoutSummary], window: AnalysisWindow) -> String {
        let distribution = MuscleLoad.merged(summaries.flatMap(\.muscleLoads))
        guard !distribution.isEmpty else {
            return "## Muscle groups\nNo exercises in this window could be classified."
        }

        let total = distribution.reduce(0) { $0 + $1.volumeKg }
        let sessionCounts = MuscleGroupFrequency.sessionCounts(in: summaries)
        let perWeek = MuscleGroupFrequency.sessionsPerWeek(in: summaries, window: window)
        let rows = distribution.map { load -> String in
            // Sets carry the groups that produce no kilograms at all. Reporting
            // a share of a zero total would be a division by zero dressed up as
            // "0%", so the share is simply omitted where it means nothing.
            let share = total > 0
                ? " (\(Int((load.volumeKg / total * 100).rounded()))% of volume)"
                : ""
            let sessions = sessionCounts[load.group] ?? 0
            let frequency = MuscleGroupFrequency.string(perWeek[load.group] ?? 0)
            return "- \(load.group.displayName): \(PromptFigures.kg(load.volumeKg))\(share), "
                + "\(load.setCount) working sets, "
                + "trained in \(sessions) \(sessions == 1 ? "session" : "sessions") (\(frequency) per week)"
        }
        return (["## Muscle groups (last \(window.weeks) weeks)"] + rows).joined(separator: "\n")
    }

    /// The equally long window before the analysed one, for trend only.
    /// Deliberately just the headline figures: the model needs a direction of
    /// travel here, not a second full breakdown competing with the recent
    /// window for attention.
    private static func comparisonSection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String {
        let header = "## Previous \(window.weeks) weeks "
            + "(\(formatter.string(start)) to \(formatter.string(end))), for comparison"
        guard !summaries.isEmpty else {
            return header + "\nNo workouts recorded. This may be a break, or simply the "
                + "start of the recorded history — do not assume which."
        }

        let days = PromptFigures.trainingDays(summaries, calendar: calendar)
        return """
        \(header)
        Sessions: \(summaries.count)
        Training days: \(days) (\(PromptFigures.frequency(days, window: window)) per week)
        Total volume: \(PromptFigures.kg(PromptFigures.volume(of: summaries)))
        """
    }

    private static func sessionSection(
        _ summaries: [WorkoutSummary],
        days: PromptDayFormatter,
        detail: AnalysisPromptDetail = .full
    ) -> String {
        let sorted = summaries.sorted { $0.startTime > $1.startTime }
        let listed = sorted.prefix(max(0, detail.listedSessions))
        let rows = listed.map { sessionRow($0, days: days) }
        let omitted = sorted.count - listed.count
        // Through `CountFormatter` like every other counted noun in the
        // prompt: with the budget's 20-session rung the boundary case is
        // reachable, and "1 older sessions" is the kind of sentence that makes
        // a model distrust the figures around it.
        let footer = omitted > 0
            ? ["(\(CountFormatter.labelled(omitted, singular: "older session")) in this window omitted)"]
            : []
        return (["## Sessions (newest first)"] + rows + footer).joined(separator: "\n")
    }

    /// One session of the list: its volume and set counts, or — for a source
    /// that logs no sets — what it did record.
    ///
    /// The honest row states the gap and then the figures the source actually
    /// carries, so the session is neither invented into sets nor reduced to a
    /// title: "no sets logged (Strava records whole sessions), 48 min, mean
    /// heart rate 132 bpm". Anything the source left out is left out here,
    /// like everywhere else in the prompt (US-15 AC7).
    private static func sessionRow(_ summary: WorkoutSummary, days: PromptDayFormatter) -> String {
        let prefix = "- \(days.string(summary.startTime)) \(summary.title): "
        guard summary.source.isEnduranceSource else {
            return prefix + "\(PromptFigures.kg(summary.volumeKg)), "
                + "\(summary.exerciseCount) exercises, \(summary.countedSetCount) working sets"
        }
        var parts = ["no sets logged (\(summary.source.displayName) records whole sessions)"]
        if let time = summary.durationSeconds.flatMap(PromptFigures.duration) {
            parts.append(time)
        }
        if let rate = summary.cardio?.averageHeartRate, let text = PromptFigures.heartRate(rate) {
            parts.append("mean heart rate \(text)")
        }
        return prefix + parts.joined(separator: ", ")
    }

    // MARK: - Exercises (#173)

    /// Per-exercise working weights, reps, RPE and the 1RM trend — the figures
    /// a concrete recommendation starts from (US-3 AC7, US-14 AC7).
    ///
    /// Without this section the model knows session totals but not a single
    /// working weight, so any "go from 60 to 62.5 kg" it produced would be
    /// invented. Names are passed exactly as the cache spells them: they are
    /// the key the recommendation cards are validated against (#175).
    ///
    /// Each line opens with the exercise name followed by a colon, so a name
    /// that itself contains parentheses stays unambiguous.
    private static func exerciseSection(
        _ exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        window: AnalysisWindow,
        from start: Date,
        days: PromptDayFormatter,
        detail: AnalysisPromptDetail = .full
    ) -> String {
        let header = "## Exercises (last \(window.weeks) weeks)"
        let listed = AnalysisPromptBuilder.promptedExercises(from: exercises, limit: detail.listedExercises)
        let rows = listed.compactMap { exercise -> String? in
            guard let progression = progressions[exercise.id],
                  let listing = AnalysisPromptBuilder.listing(progression, from: start)
            else { return nil }
            return exerciseRow(exercise, listing: listing, days: days)
        }
        guard !rows.isEmpty else {
            return header + "\nNo exercise-level data is available for this window. "
                + "Do not name exercises or weights."
        }

        let legend = "Each line starts with the exercise name exactly as logged, then the "
            + "heaviest working set (weight × reps) of its most recent session with working "
            + "sets. e1RM is the Epley estimate from a session's best set, at the first and at "
            + "the most recent session in this window that has one. Each line ends with the "
            + "rep target of my routine for the exercise, whether I beat it by two or more reps "
            + "in the last two sessions, and after \"Next:\" the load range a progression may "
            + "move to — or the instruction to progress reps instead of weight."
        // Counted against the cap, not against the rows: a listed exercise
        // skipped for want of a progression was not cut by the cap, and
        // calling it "omitted" would misstate why it is missing.
        let omitted = max(0, exercises.count - detail.listedExercises)
        let footer = omitted > 0
            ? ["(\(rows.count) exercises with the most volume listed; \(omitted) more in this window omitted)"]
            : []
        return ([header, legend] + rows + footer).joined(separator: "\n")
    }

    private static func exerciseRow(
        _ exercise: ExerciseSummary,
        listing: (inWindow: ExerciseProgression, last: ExerciseHistoryEntry),
        days: PromptDayFormatter
    ) -> String {
        let (inWindow, last) = listing

        // The working set leads, right after the name: it is the value a
        // recommendation starts from, and "Bench Press: 60 kg × 5" reads as
        // one fact rather than two figures to be paired up.
        var parts = [
            "- \(exercise.title): \(lastSessionSummary(last)) "
                + "(most recent session, \(days.string(last.sessionStart)))",
            "\(exercise.muscleGroup.displayName), \(exercise.sessionCount) sessions, "
                + "\(PromptFigures.kg(exercise.volumeKg))",
        ]
        let points = inWindow.points
        if let first = points.first, let latest = points.last {
            let now = PlainNumberFormatter.string(latest.estimatedOneRepMaxKg, decimals: 1)
            if points.count == 1 {
                parts.append("e1RM \(now) kg (one session, no trend yet)")
            } else {
                let then = PlainNumberFormatter.string(first.estimatedOneRepMaxKg, decimals: 1)
                let delta = latest.estimatedOneRepMaxKg - first.estimatedOneRepMaxKg
                parts.append(
                    "e1RM \(then) kg at first session in window, \(now) kg now "
                        + "(\(PromptFigures.signed(delta)))"
                )
            }
            parts.append(plateauVerdict(inWindow))
        }
        parts.append(contentsOf: progressionParts(exercise, listing: listing))
        return parts.joined(separator: ". ") + "."
    }

    /// The rep target, the 2-for-2 verdict and what may come next (ADR-013,
    /// #232): the load range where the rule is met and a step exists, and
    /// "progress reps, not weight" everywhere else.
    ///
    /// Read from the same `ListedExercise` the validation of #233 is handed
    /// — `ListedExercise.make(title:muscleGroup:listing:)` builds both — so
    /// the range the model is shown and the range a card is checked against
    /// are one computation.
    ///
    /// The missing target is stated as such, not skipped: rule 6 tells the
    /// model that an unapplicable rule is not a met one, and it can only act
    /// on that if the line says which of the two it is. `.met` and `.notMet`
    /// always come with a target (`TwoForTwoCondition.evaluate` checks the
    /// targets before it counts), so the line never claims one it cannot
    /// name; the `nil` arm below is the guard for that, not a case.
    private static func progressionParts(
        _ exercise: ExerciseSummary,
        listing: (inWindow: ExerciseProgression, last: ExerciseHistoryEntry)
    ) -> [String] {
        let listed = ListedExercise.make(title: exercise.title, muscleGroup: exercise.muscleGroup, listing: listing)
        let target = TwoForTwoCondition.latestTarget(in: listing.inWindow.sessions)
        let margin = TwoForTwoCondition.requiredMargin
        let pair = TwoForTwoCondition.requiredSessions
        let reps = "Next: progress reps, not weight"
        switch (listed.twoForTwo, target) {
        case let (.met, target?):
            let next = ProgressionBand.range(for: listed).map { "Next: \(ProgressionBand.text($0))" }
                ?? "Next: progress reps, no load step is logged for this exercise"
            return ["Rep target \(target), beaten by \(margin)+ reps in the last \(pair) sessions", next]
        case let (.notMet, target?):
            return ["Rep target \(target), not yet beaten by \(margin)+ reps in \(pair) consecutive sessions", reps]
        case let (.notCheckable, target?):
            // A target on the latest session alone is stated as such: "no
            // target" would be untrue, and "not met" would be a verdict the
            // rule never reached.
            return ["Rep target \(target), not on file for both of the last \(pair) sessions", reps]
        case (_, nil):
            return ["No rep target on file", reps]
        }
    }

    /// The session's working weight, and the mean RPE over the counted sets
    /// that logged one.
    ///
    /// The working weight is `ExerciseHistoryEntry.heaviestWorkingSet` — the
    /// same rule the validation of #175 reads, so the figure a card starts
    /// from and the figure the prompt stated cannot drift apart.
    private static func lastSessionSummary(_ session: ExerciseHistoryEntry) -> String {
        let counted = session.sets.filter(\.countsTowardsVolume)
        var summary: String
        if let working = session.heaviestWorkingSet {
            summary = "\(working.weightText) kg × \(working.reps)"
        } else if counted.isEmpty {
            summary = "no working sets logged"
        } else if let reps = counted.compactMap(\.reps).max(), reps > 0 {
            summary = "no weight logged, best set \(reps) reps"
        } else {
            summary = "no set with both weight and reps logged"
        }

        let rpes = counted.compactMap(\.rpe)
        if !rpes.isEmpty {
            let mean = rpes.reduce(0, +) / Double(rpes.count)
            summary += ", mean RPE \(PlainNumberFormatter.string(mean, decimals: 1))"
        }
        return summary
    }

    /// `ExerciseProgression.isPlateaued`, with the case it cannot decide said
    /// out loud: a "no" over three sessions would claim progress nobody
    /// measured.
    private static func plateauVerdict(_ progression: ExerciseProgression) -> String {
        guard progression.points.count > ExerciseProgression.plateauSessionCount else {
            return "Plateau: too few sessions to tell"
        }
        return progression.isPlateaued
            ? "Plateau: yes, no new e1RM best in the last \(ExerciseProgression.plateauSessionCount) sessions"
            : "Plateau: no"
    }
}

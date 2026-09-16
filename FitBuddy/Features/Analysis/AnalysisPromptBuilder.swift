import Foundation

/// Turns the cached workout window into the prompt pair `InferenceService`
/// sends to Claude (US-3, #30).
///
/// Everything the model sees comes from this one user's own cache. There are
/// no population averages, strength standards or "typical" volumes anywhere in
/// the output, and the system prompt forbids inventing them — US-3 AC3 is a
/// property of the prompt, not of the model's goodwill.
enum AnalysisPromptBuilder {
    /// Sessions listed individually. Four weeks of training fits comfortably,
    /// and even a widened 13-week window rarely fills it; the cap only guards
    /// the tail, where sessions add tokens but no signal — the aggregates
    /// above already carry the older ones.
    private static let maxListedSessions = 30

    /// Exercises listed individually in the Exercises section (#173).
    ///
    /// Ten because the section exists for the recommendation, and a
    /// recommendation for the next block names a handful of lifts, not a
    /// whole programme. Ranked by volume, so the lifts the window was built
    /// around come first; every exercise past the cap costs a line of tokens
    /// for a movement the model would hardly recommend on. The prompt names
    /// the cap, so a missing exercise reads as omitted, not as untrained.
    static let maxListedExercises = 10

    /// The largest logged step still offered as an increment, as a share of
    /// the latest working weight (#173).
    ///
    /// The gap between two logged weights is only an increment when it is a
    /// small one: 8 and 12 kg dumbbells are two different exercises' worth of
    /// load, not a 4 kg step — that would be +33 % in one session. Past this
    /// share the step is left out, and rule 6 falls back to reps.
    static let maxStepShare = 0.10

    /// Builds the prompt pair from the cached window.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order. Anything outside the two
    ///     analysis windows is ignored, so the dashboard's 90-day read can be
    ///     passed in unchanged. Strava sessions are ignored as well — see
    ///     `strengthSessions(in:)`.
    ///   - exercises: The movements of the analysed window, rolled up per
    ///     exercise (`exerciseSummaries(since:)` with the window's start). The
    ///     prompt lists the top `maxListedExercises` of them by volume.
    ///   - progressions: The progression of each listed movement, keyed by
    ///     `ExerciseSummary.id`. Sessions before the window's start are
    ///     ignored, so a wider read changes nothing. A listed movement without
    ///     an entry is skipped rather than described from its totals alone.
    ///   - window: The window actually analysed — the default, or a wider rung
    ///     of the fallback ladder when the last four weeks are empty (#87).
    ///   - now: Injectable clock, so the windows are testable.
    ///   - calendar: Decides where a day starts, so training days follow the
    ///     user's time zone.
    static func make(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary] = [],
        progressions: [String: ExerciseProgression] = [:],
        window: AnalysisWindow = .default,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalysisPrompt {
        AnalysisPrompt(
            system: systemPrompt,
            user: userPrompt(
                summaries: strengthSessions(in: summaries),
                exercises: exercises,
                progressions: progressions,
                window: window,
                now: now,
                calendar: calendar
            )
        )
    }

    /// The sessions the analysis is about: Hevy's, not Strava's or Polar's
    /// (US-5, #144).
    ///
    /// The system prompt describes strength training, and rule 5 explains a
    /// 0 kg line as bodyweight or timed work. A run passed through as a
    /// session would be read exactly that way — "1 exercise, 1 working set,
    /// 0 kg" — and someone running four times a week would be told about a
    /// volume collapse that never happened (US-3 AC3). Cardio context is v1
    /// material; for v0 the figures at least have to be right, so the same
    /// filter decides the session count `AnalysisContext` reports (US-6).
    static func strengthSessions(in summaries: [WorkoutSummary]) -> [WorkoutSummary] {
        summaries.filter { !$0.source.isEnduranceSource }
    }

    /// The strength sessions of the analysed window — what every figure about
    /// the recent window is computed over, in the prompt and in the check of
    /// the model's answer against it (#175).
    static func analysedSessions(
        in summaries: [WorkoutSummary],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [WorkoutSummary] {
        let start = window.start(endingAt: now, calendar: calendar)
        return strengthSessions(in: summaries).filter { $0.startTime >= start }
    }

    /// The movements the Exercises section lists: the top
    /// `maxListedExercises` by volume in the window (#173).
    ///
    /// Public to the feature so `AnalysisViewModel` reads progressions for
    /// exactly these and no others. Ties are broken by session count, then by
    /// title, so the same cache always yields the same prompt — and
    /// bodyweight movements, which carry no kilograms, still rank by how often
    /// they were trained.
    static func promptedExercises(from exercises: [ExerciseSummary]) -> [ExerciseSummary] {
        let ranked = exercises.sorted { lhs, rhs in
            if lhs.volumeKg != rhs.volumeKg { return lhs.volumeKg > rhs.volumeKg }
            if lhs.sessionCount != rhs.sessionCount { return lhs.sessionCount > rhs.sessionCount }
            return lhs.title < rhs.title
        }
        return Array(ranked.prefix(maxListedExercises))
    }

    // MARK: - System

    /// The ground rules. Spelled out rather than implied: the model has no way
    /// to know that FitBuddy is not a medical product, that the muscle split is
    /// a keyword heuristic, or that bodyweight work carries load without
    /// kilograms — and each of those, unstated, produces confident nonsense.
    static let systemPrompt = """
    You are FitBuddy's training assistant. You analyse one person's own \
    strength-training history and give them a concrete recommendation for \
    their next training block.

    Ground rules:

    1. FitBuddy is not a medical product. Do not diagnose, and do not give \
    medical, nutritional or rehabilitation advice. Do not interpret pain, \
    injury or symptoms. If the data points at something health-related, say \
    plainly that this is outside what FitBuddy can assess and that a \
    qualified professional is the right address.

    2. Judge this data only against itself. The person's own history is the \
    only reference point you have: compare the recent window with the \
    previous one and name what these numbers show. Never invoke population \
    averages, strength standards, "typical" volumes for a body weight, sex or \
    age, or any benchmark from outside this prompt. You were given none, and \
    inventing one would present a guess as a fact.

    3. Work only with what is stated. Do not assume a training goal, training \
    age, body weight, equipment or weekly schedule that is not in the data. \
    Where a recommendation would depend on something you were not told, say \
    what you would need to know instead of filling the gap.

    4. Muscle groups are classified heuristically from exercise names and are \
    sometimes wrong. Treat the split as an indication, not a measurement.

    5. Volume is the sum of weight x reps over working sets; warm-up sets are \
    excluded. Bodyweight and time-based work contributes sets but no \
    kilograms, so a group can carry real training load while showing little \
    or no volume. Never read a low kg figure as "untrained" on its own.

    6. Name only exercises and weights from the Exercises section. Spell an \
    exercise exactly as it is listed there, and start any load change from \
    the weight listed for its most recent session. Never name an exercise or \
    a weight that section does not contain. Increase barbell exercises in \
    steps of 2.5 kg; for every other exercise increase by at most the \
    smallest step listed for it, and where none is listed, progress reps \
    rather than weight.

    Answer in English, as one JSON object that follows the response schema:

    - headline: one short sentence stating the verdict.
    - verdict: "progress" when the data supports adding load or reps, \
    "recover" when rest has to come first, "hold" when neither is justified \
    yet.
    - lead: the key takeaway in one to three sentences, at most about 50 \
    words. It must stand on its own: someone who reads only the headline and \
    the lead knows what to do next.
    - summary: the full analysis as plain prose under 200 words, readable \
    without the cards: first what stands out in the data, then a concrete \
    recommendation for the next block.
    - cards: zero to four cards, most important first. Add a card only when \
    the data supports it; when the data is too thin for any, return an empty \
    array — the lead and the summary carry the answer. Use "progression" for \
    a load increase on one exercise: fromKg is the weight listed for its most \
    recent session, toKg the new weight, reasoning one sentence. Use \
    "recovery" when rest comes before any progression, with the rest you \
    recommend in suggestedRestHours. Use "imbalance" when two muscle groups \
    are trained at clearly different frequencies, naming each group and its \
    sessions per week exactly as the Muscle groups section lists them. Use \
    "note" for anything else worth saying, including a rep progression \
    without a weight change. Every card follows the ground rules \
    above; a recommendation you cannot ground in the data does not become a \
    card.

    Write the fields in this order.

    Never write placeholder or filler text in any field. A field you have \
    nothing to say in is not a reason to invent something; leave a card out \
    instead.
    """

    // MARK: - User

    private static func userPrompt(
        summaries: [WorkoutSummary],
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar
    ) -> String {
        let recentStart = window.start(endingAt: now, calendar: calendar)
        let previousStart = window.previousStart(endingAt: now, calendar: calendar)

        let recent = analysedSessions(in: summaries, window: window, now: now, calendar: calendar)
        let previous = summaries.filter { $0.startTime >= previousStart && $0.startTime < recentStart }

        let days = DayFormatter(calendar: calendar)
        var intro = "Here is my own training data. Analyse it and tell me what to do next."
        // A widened window means the user did not train for at least the last
        // four weeks. Left unsaid, the model reads the window as a normal one
        // and recommends progression across a break it never noticed (#87).
        if !window.isDefault {
            intro += " I have not trained in the last \(AnalysisWindow.default.weeks) weeks, "
                + "so this covers the last \(window.weeks) weeks instead. Address that break "
                + "explicitly and treat the training before it as what I am returning from."
        }

        // An empty window turns every figure into a zero, which reads as
        // "trained nothing" rather than "nothing recorded" — including the
        // window header itself. Saying it once, plainly, is shorter and truer.
        guard !recent.isEmpty else {
            return [
                intro,
                "## Last \(window.weeks) weeks (\(days.string(recentStart)) to \(days.string(now)))",
                "No workouts are recorded in this window. Say so plainly and do not "
                    + "infer a training history from the absence of data.",
            ].joined(separator: "\n\n")
        }

        var sections: [String] = [
            intro,
            windowSection(recent, window: window, from: recentStart, to: now, calendar: calendar, days: days),
        ]
        sections.append(weeklySection(recent, window: window, now: now, calendar: calendar, days: days))
        sections.append(muscleSection(recent, window: window))
        sections.append(
            comparisonSection(
                previous,
                window: window,
                from: previousStart,
                to: recentStart,
                calendar: calendar,
                days: days
            )
        )
        sections.append(sessionSection(recent, days: days))
        sections.append(
            exerciseSection(
                exercises,
                progressions: progressions,
                window: window,
                from: recentStart,
                days: days
            )
        )

        return sections.joined(separator: "\n\n")
    }

    private static func windowSection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        days formatter: DayFormatter
    ) -> String {
        let days = trainingDays(summaries, calendar: calendar)
        return """
        ## Last \(window.weeks) weeks (\(formatter.string(start)) to \(formatter.string(end)))
        Sessions: \(summaries.count)
        Training days: \(days) (\(frequency(days, window: window)) per week)
        Total volume: \(kg(volume(of: summaries)))
        """
    }

    /// Per-week figures, newest first. The totals alone cannot show whether
    /// the window's training was spread evenly or crammed into one week — and
    /// that difference changes the recommendation.
    private static func weeklySection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar,
        days: DayFormatter
    ) -> String {
        let weeks = (0..<window.weeks).map { index -> String in
            let start = AnalysisWindow.weekStart(index, endingAt: now, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let inWeek = summaries.filter { $0.startTime >= start && $0.startTime < end }
            let label = index == 0 ? "most recent" : "\(index + 1) weeks back"
            return "- Week starting \(days.string(start)) (\(label)): "
                + "\(inWeek.count) sessions, \(kg(volume(of: inWeek)))"
        }
        return (["## Volume per week"] + weeks).joined(separator: "\n")
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
            return "- \(load.group.displayName): \(kg(load.volumeKg))\(share), \(load.setCount) working sets, "
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
        days formatter: DayFormatter
    ) -> String {
        let header = "## Previous \(window.weeks) weeks "
            + "(\(formatter.string(start)) to \(formatter.string(end))), for comparison"
        guard !summaries.isEmpty else {
            return header + "\nNo workouts recorded. This may be a break, or simply the "
                + "start of the recorded history — do not assume which."
        }

        let days = trainingDays(summaries, calendar: calendar)
        return """
        \(header)
        Sessions: \(summaries.count)
        Training days: \(days) (\(frequency(days, window: window)) per week)
        Total volume: \(kg(volume(of: summaries)))
        """
    }

    private static func sessionSection(
        _ summaries: [WorkoutSummary],
        days: DayFormatter
    ) -> String {
        let sorted = summaries.sorted { $0.startTime > $1.startTime }
        let listed = sorted.prefix(maxListedSessions)
        let rows = listed.map { summary in
            "- \(days.string(summary.startTime)) \(summary.title): \(kg(summary.volumeKg)), "
                + "\(summary.exerciseCount) exercises, \(summary.countedSetCount) working sets"
        }
        let omitted = sorted.count - listed.count
        let footer = omitted > 0 ? ["(\(omitted) older sessions in this window omitted)"] : []
        return (["## Sessions (newest first)"] + rows + footer).joined(separator: "\n")
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
        days: DayFormatter
    ) -> String {
        let header = "## Exercises (last \(window.weeks) weeks)"
        let rows = promptedExercises(from: exercises).compactMap { exercise -> String? in
            guard let progression = progressions[exercise.id],
                  let listing = listing(progression, from: start)
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
            + "the most recent session in this window that has one."
        let omitted = exercises.count - rows.count
        let footer = omitted > 0
            ? ["(\(rows.count) exercises with the most volume listed; \(omitted) more in this window omitted)"]
            : []
        return ([header, legend] + rows + footer).joined(separator: "\n")
    }

    /// The exercises the Exercises section lists, each reduced to the
    /// working set its line states — what a progression card is checked
    /// against (#175).
    ///
    /// Walks the same ranking, the same lookup and the same session choice as
    /// the section itself, so a movement is here exactly when it has a line,
    /// and with exactly the weight that line names.
    static func listedExercises(
        exercises: [ExerciseSummary],
        progressions: [String: ExerciseProgression],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar = .current
    ) -> [ListedExercise] {
        let start = window.start(endingAt: now, calendar: calendar)
        return promptedExercises(from: exercises).compactMap { exercise in
            guard let progression = progressions[exercise.id],
                  let listing = listing(progression, from: start)
            else { return nil }
            return ListedExercise(
                title: exercise.title,
                muscleGroup: exercise.muscleGroup,
                workingSet: listing.last.heaviestWorkingSet
            )
        }
    }

    /// A movement's sessions inside the window, and the session its line
    /// starts from. `nil` when the window holds none of its sessions.
    private static func listing(
        _ progression: ExerciseProgression,
        from start: Date
    ) -> (inWindow: ExerciseProgression, last: ExerciseHistoryEntry)? {
        // Rebuilt over the window alone, so the trend and the plateau verdict
        // describe the same sessions as every other figure in the prompt —
        // whatever range the progression was read over.
        let inWindow = ExerciseProgression(
            id: progression.id,
            title: progression.title,
            sessions: progression.sessions.filter { $0.sessionStart >= start }
        )
        // The most recent session that logged working sets: one holding only
        // warm-ups would report "nothing logged" above a trend drawn from the
        // sessions before it.
        guard let last = inWindow.sessions.last(where: { $0.countedSetCount > 0 })
            ?? inWindow.sessions.last
        else { return nil }
        return (inWindow, last)
    }

    private static func exerciseRow(
        _ exercise: ExerciseSummary,
        listing: (inWindow: ExerciseProgression, last: ExerciseHistoryEntry),
        days: DayFormatter
    ) -> String {
        let (inWindow, last) = listing

        // The working set leads, right after the name: it is the value a
        // recommendation starts from, and "Bench Press: 60 kg × 5" reads as
        // one fact rather than two figures to be paired up.
        var parts = [
            "- \(exercise.title): \(lastSessionSummary(last)) "
                + "(most recent session, \(days.string(last.sessionStart)))",
            "\(exercise.muscleGroup.displayName), \(exercise.sessionCount) sessions, \(kg(exercise.volumeKg))",
        ]
        let points = inWindow.points
        if let first = points.first, let latest = points.last {
            let now = PlainWeightFormatter.string(latest.estimatedOneRepMaxKg, decimals: 1)
            if points.count == 1 {
                parts.append("e1RM \(now) kg (one session, no trend yet)")
            } else {
                let then = PlainWeightFormatter.string(first.estimatedOneRepMaxKg, decimals: 1)
                let delta = latest.estimatedOneRepMaxKg - first.estimatedOneRepMaxKg
                parts.append("e1RM \(then) kg at first session in window, \(now) kg now (\(signed(delta)))")
            }
            parts.append(plateauVerdict(inWindow))
        }
        if let latest = last.heaviestWorkingSet,
           let step = smallestStep(in: inWindow.sessions, latest: latest) {
            parts.append("Smallest logged step: \(PlainWeightFormatter.string(step)) kg")
        }
        return parts.joined(separator: ". ") + "."
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
            summary += ", mean RPE \(PlainWeightFormatter.string(mean, decimals: 1))"
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

    /// The smallest difference between two distinct working weights the user
    /// logged for this exercise in the window — the increment their gym
    /// actually offers, which rule 6 caps a load increase at.
    ///
    /// Only working sets count, the sets the working weight itself is taken
    /// from: a carry's weight next to a press's would be a step between two
    /// different kinds of set. `nil` when fewer than two distinct weights were
    /// logged, and when the step is larger than `maxStepShare` of `latest` —
    /// a gap that size is a change of equipment, not an increment.
    private static func smallestStep(in sessions: [ExerciseHistoryEntry], latest: WorkingSet) -> Double? {
        // Rounded first, so two floating-point spellings of 62.5 cannot turn
        // into a step of 0.0000001 kg.
        let weights = Set(sessions.flatMap(\.workingSets).map(\.roundedWeightKg)).sorted()
        guard let step = zip(weights, weights.dropFirst()).map({ $1 - $0 }).min(),
              step <= latest.weightKg * maxStepShare
        else { return nil }
        return step
    }

    // MARK: - Aggregation

    private static func volume(of summaries: [WorkoutSummary]) -> Double {
        summaries.reduce(0) { $0 + $1.volumeKg }
    }

    /// Calendar days carrying at least one session — two sessions on one day
    /// are one training day.
    private static func trainingDays(_ summaries: [WorkoutSummary], calendar: Calendar) -> Int {
        Set(summaries.map { calendar.startOfDay(for: $0.startTime) }).count
    }

    // MARK: - Formatting

    /// Volume without grouping separators.
    ///
    /// `VolumeFormatter` is the dashboard's, and it follows the device locale —
    /// which would put `48'320` in front of the model on a Swiss device and
    /// `48,320` on a US one, for identical training. A prompt has no reader to
    /// charm; it needs one unambiguous form.
    private static func kg(_ kilograms: Double) -> String {
        "\(Int(kilograms.rounded())) kg"
    }

    /// A 1RM change with its direction spelled out.
    private static func signed(_ kilograms: Double) -> String {
        let text = PlainWeightFormatter.string(abs(kilograms), decimals: 1)
        guard text != "0" else { return "no change" }
        return (kilograms > 0 ? "+" : "-") + text + " kg"
    }

    private static func frequency(_ trainingDays: Int, window: AnalysisWindow) -> String {
        let perWeek = Double(trainingDays) / Double(window.weeks)
        return String(format: "%.1f days", perWeek)
    }

    /// One formatter per prompt, handed to the sections that need it.
    ///
    /// A prompt renders up to ~40 dates, and `DateFormatter` is expensive to
    /// create; it is also not safe to share across calls, so the instance lives
    /// exactly as long as the build that owns it.
    private struct DayFormatter {
        private let formatter: DateFormatter

        init(calendar: Calendar) {
            let formatter = DateFormatter()
            // Fixed locale and the window's own time zone: the date is data
            // here, not display text, and must not shift with the device's
            // region.
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            self.formatter = formatter
        }

        func string(_ date: Date) -> String {
            formatter.string(from: date)
        }
    }
}

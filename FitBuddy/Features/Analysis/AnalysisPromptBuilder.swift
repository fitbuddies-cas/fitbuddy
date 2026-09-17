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

    /// Builds the prompt pair from the cached window.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order. Anything outside the two
    ///     analysis windows is ignored, so the dashboard's 90-day read can be
    ///     passed in unchanged. Strava sessions are ignored as well — see
    ///     `strengthSessions(in:)`.
    ///   - window: The window actually analysed — the default, or a wider rung
    ///     of the fallback ladder when the last four weeks are empty (#87).
    ///   - now: Injectable clock, so the windows are testable.
    ///   - calendar: Decides where a day starts, so training days follow the
    ///     user's time zone.
    ///   - profile: What the user said they train for (US-13). An empty
    ///     profile — the default, and every install that never answered —
    ///     leaves the prompt byte-for-byte as it was without one.
    static func make(
        summaries: [WorkoutSummary],
        window: AnalysisWindow = .default,
        now: Date = Date(),
        calendar: Calendar = .current,
        profile: TrainingProfile = TrainingProfile()
    ) -> AnalysisPrompt {
        AnalysisPrompt(
            system: systemPrompt,
            user: userPrompt(
                summaries: strengthSessions(in: summaries),
                window: window,
                now: now,
                calendar: calendar,
                profile: profile
            )
        )
    }

    // MARK: - Profile

    /// The user's own answers, as facts about them (US-13 AC3, #192) — or
    /// nothing at all.
    ///
    /// `nil` rather than a heading with nothing under it: "Profile: —" reads
    /// to the model as a statement about the person, and a half profile
    /// states only the half that was answered.
    ///
    /// The closing line is the one that matters most. The analysis reads
    /// strength sessions only, so a runner with the goal "improve endurance"
    /// would otherwise hand the model a goal that asks for context the prompt
    /// does not carry — and rule 3 of the system prompt is the only thing
    /// standing between that gap and an invented one. Saying it here keeps
    /// the profile inside the rules instead of leaning against them.
    static func profileSection(_ profile: TrainingProfile) -> String? {
        var lines: [String] = []
        if let goal = profile.goal {
            lines.append("Goal: \(goal.displayName.lowercased())")
        }
        if let experience = profile.experience {
            lines.append("Strength training experience: \(experience.displayName.lowercased())")
        }
        guard !lines.isEmpty else { return nil }
        lines.append(
            "The data below covers my strength sessions only; do not assume anything "
                + "about other training I may do."
        )
        return (["## Profile"] + lines).joined(separator: "\n")
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

    Answer in English and keep it under 200 words: first what stands out in \
    the data, then a concrete recommendation for the next block.
    """

    // MARK: - User

    private static func userPrompt(
        summaries: [WorkoutSummary],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar,
        profile: TrainingProfile
    ) -> String {
        let recentStart = window.start(endingAt: now, calendar: calendar)
        let previousStart = window.previousStart(endingAt: now, calendar: calendar)

        let recent = summaries.filter { $0.startTime >= recentStart }
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
        // Facts about the person come before facts about the data, and only
        // when there are any: `compactMap` drops the section, not its heading.
        let opening = [intro, profileSection(profile)].compactMap { $0 }

        guard !recent.isEmpty else {
            return (opening + [
                "## Last \(window.weeks) weeks (\(days.string(recentStart)) to \(days.string(now)))",
                "No workouts are recorded in this window. Say so plainly and do not "
                    + "infer a training history from the absence of data.",
            ]).joined(separator: "\n\n")
        }

        var sections: [String] = opening + [
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

    private static func muscleSection(_ summaries: [WorkoutSummary], window: AnalysisWindow) -> String {
        let distribution = MuscleLoad.merged(summaries.flatMap(\.muscleLoads))
        guard !distribution.isEmpty else {
            return "## Muscle groups\nNo exercises in this window could be classified."
        }

        let total = distribution.reduce(0) { $0 + $1.volumeKg }
        let rows = distribution.map { load -> String in
            // Sets carry the groups that produce no kilograms at all. Reporting
            // a share of a zero total would be a division by zero dressed up as
            // "0%", so the share is simply omitted where it means nothing.
            let share = total > 0
                ? " (\(Int((load.volumeKg / total * 100).rounded()))% of volume)"
                : ""
            return "- \(load.group.displayName): \(kg(load.volumeKg))\(share), \(load.setCount) working sets"
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

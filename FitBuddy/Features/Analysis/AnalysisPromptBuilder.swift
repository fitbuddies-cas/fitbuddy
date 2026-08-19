import Foundation

/// Turns the cached workout window into the prompt pair `InferenceService`
/// sends to Claude (US-3, #30).
///
/// Everything the model sees comes from this one user's own cache. There are
/// no population averages, strength standards or "typical" volumes anywhere in
/// the output, and the system prompt forbids inventing them — US-3 AC3 is a
/// property of the prompt, not of the model's goodwill.
enum AnalysisPromptBuilder {
    /// Sessions listed individually. Four weeks of training fits comfortably;
    /// the cap only guards against a cache holding far more than a person can
    /// train, where the tail adds tokens but no signal.
    private static let maxListedSessions = 30

    /// Builds the prompt pair from the cached window.
    ///
    /// - Parameters:
    ///   - summaries: Cached workouts, in any order. Anything outside the two
    ///     analysis windows is ignored, so the dashboard's 90-day read can be
    ///     passed in unchanged.
    ///   - now: Injectable clock, so the windows are testable.
    ///   - calendar: Decides where a day starts, so training days follow the
    ///     user's time zone.
    static func make(
        summaries: [WorkoutSummary],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalysisPrompt {
        AnalysisPrompt(
            system: systemPrompt,
            user: userPrompt(summaries: summaries, now: now, calendar: calendar)
        )
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
        now: Date,
        calendar: Calendar
    ) -> String {
        let recentStart = AnalysisWindow.start(endingAt: now, calendar: calendar)
        let previousStart = AnalysisWindow.previousStart(endingAt: now, calendar: calendar)

        let recent = summaries.filter { $0.startTime >= recentStart }
        let previous = summaries.filter { $0.startTime >= previousStart && $0.startTime < recentStart }

        var sections: [String] = [
            "Here is my own training data. Analyse it and tell me what to do next.",
            windowSection(recent, from: recentStart, to: now, calendar: calendar),
        ]

        // An empty window makes every section below it a list of zeroes, which
        // reads as "trained nothing" rather than "nothing recorded". Saying it
        // once, plainly, is both shorter and truer.
        guard !recent.isEmpty else {
            sections.append(
                "No workouts are recorded in this window. Say so plainly and do not "
                    + "infer a training history from the absence of data."
            )
            return sections.joined(separator: "\n\n")
        }

        sections.append(weeklySection(recent, now: now, calendar: calendar))
        sections.append(muscleSection(recent))
        sections.append(
            comparisonSection(previous, from: previousStart, to: recentStart, calendar: calendar)
        )
        sections.append(sessionSection(recent, calendar: calendar))

        return sections.joined(separator: "\n\n")
    }

    private static func windowSection(
        _ summaries: [WorkoutSummary],
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> String {
        let days = trainingDays(summaries, calendar: calendar)
        return """
        ## Last 4 weeks (\(day(start, calendar)) to \(day(end, calendar)))
        Sessions: \(summaries.count)
        Training days: \(days) (\(frequency(days)) per week)
        Total volume: \(kg(volume(of: summaries)))
        """
    }

    /// Per-week figures, newest first. The totals alone cannot show whether
    /// four weeks of training were spread evenly or crammed into one — and
    /// that difference changes the recommendation.
    private static func weeklySection(
        _ summaries: [WorkoutSummary],
        now: Date,
        calendar: Calendar
    ) -> String {
        let weeks = (0..<Int(AnalysisWindow.weeks)).map { index -> String in
            let start = AnalysisWindow.weekStart(index, endingAt: now, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let inWeek = summaries.filter { $0.startTime >= start && $0.startTime < end }
            let label = index == 0 ? "most recent" : "\(index + 1) weeks back"
            return "- Week starting \(day(start, calendar)) (\(label)): "
                + "\(inWeek.count) sessions, \(kg(volume(of: inWeek)))"
        }
        return (["## Volume per week"] + weeks).joined(separator: "\n")
    }

    private static func muscleSection(_ summaries: [WorkoutSummary]) -> String {
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
        return (["## Muscle groups (last 4 weeks)"] + rows).joined(separator: "\n")
    }

    /// The preceding four weeks, for trend only. Deliberately just the
    /// headline figures: the model needs a direction of travel here, not a
    /// second full breakdown competing with the recent window for attention.
    private static func comparisonSection(
        _ summaries: [WorkoutSummary],
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> String {
        let header = "## Previous 4 weeks (\(day(start, calendar)) to \(day(end, calendar))), for comparison"
        guard !summaries.isEmpty else {
            return header + "\nNo workouts recorded. This may be a break, or simply the "
                + "start of the recorded history — do not assume which."
        }

        let days = trainingDays(summaries, calendar: calendar)
        return """
        \(header)
        Sessions: \(summaries.count)
        Training days: \(days) (\(frequency(days)) per week)
        Total volume: \(kg(volume(of: summaries)))
        """
    }

    private static func sessionSection(_ summaries: [WorkoutSummary], calendar: Calendar) -> String {
        let sorted = summaries.sorted { $0.startTime > $1.startTime }
        let listed = sorted.prefix(maxListedSessions)
        let rows = listed.map { summary in
            "- \(day(summary.startTime, calendar)) \(summary.title): \(kg(summary.volumeKg)), "
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

    private static func frequency(_ trainingDays: Int) -> String {
        let perWeek = Double(trainingDays) / AnalysisWindow.weeks
        return String(format: "%.1f days", perWeek)
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        // Fixed locale and the window's own time zone: the date is data here,
        // not display text, and must not shift with the device's region.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

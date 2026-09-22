import Foundation

/// How the week is put together across both domains: training days, the days
/// that carried strength, endurance or both, the longest run of consecutive
/// training days and the rest days left over (US-15 AC2, #183).
///
/// The two domain sections each describe their own half well and neither can
/// answer the question that decides most recommendations: whether the person
/// is training five days a week or ten sessions on five days, and whether the
/// hard days sit next to each other. Strength and endurance draw on the same
/// recovery, so that has to be stated once, over both.
///
/// The gate is **endurance**, not both domains. A Hevy-only cache still gets no
/// section at all, because it has to produce exactly the prompt it produced
/// before the split (#183 AC1) — but a Strava- or Polar-only cache does get one,
/// since #184 is what makes a week of six runs a recovery week and the model
/// would otherwise never be told the day count the app then overrules it on.
///
/// What is rendered depends on what is there:
///
/// - **Both domains:** the full section — the cross-domain day counts, the
///   streak and the last seven days.
/// - **Endurance only:** the streak and the last seven days. The window's own
///   training days are already in the endurance header, and "Days with strength
///   only: 0" restates the absence of a section the model was told not to
///   reason about.
/// - **Strength only:** `nil`, unchanged (#183 AC1).
enum LoadPromptSection {
    /// The week-structure section, or `nil` when the window holds no endurance
    /// session.
    ///
    /// - Parameter now: The reference the window ends at, for the
    ///   last-seven-days line (#184).
    static func section(
        strength: [WorkoutSummary],
        endurance: [WorkoutSummary],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String? {
        guard !endurance.isEmpty else { return nil }

        let strengthDays = PromptFigures.trainingDayStarts(strength, calendar: calendar)
        let enduranceDays = PromptFigures.trainingDayStarts(endurance, calendar: calendar)
        let trainingDays = strengthDays.union(enduranceDays)
        let both = strengthDays.intersection(enduranceDays)

        // Clamped to the window, as the rest days already were: a session
        // dated after `now` — a provider clock running fast, a time zone the
        // cache and the window disagree about — would otherwise read as "29 of
        // 28 training days" and a negative number of rest days.
        let counted = min(trainingDays.count, window.days)
        var lines = ["## Week structure (last \(window.weeks) weeks)"]
        if !strength.isEmpty {
            lines += [
                "Training days: \(counted) of \(window.days) "
                    + "(\(PromptFigures.frequency(counted, window: window)) per week)",
                "Days with strength only: \(strengthDays.subtracting(enduranceDays).count)",
                "Days with endurance only: \(enduranceDays.subtracting(strengthDays).count)",
                "Days with both: \(both.count)",
                "Rest days: \(window.days - counted)",
            ]
        }
        if let streak = longestStreakLine(trainingDays, calendar: calendar, days: formatter) {
            lines.append(streak)
        }
        lines.append(
            lastSevenDaysLine(strength: strength, endurance: endurance, now: now, calendar: calendar)
        )
        return lines.joined(separator: "\n")
    }

    /// The last seven days over both domains — the span US-3 AC6 judges
    /// recovery on (#184).
    ///
    /// The section's other lines cover the whole window, in which six training
    /// days say nothing about whether they were this week or spread over four.
    /// Without this line the model would have to guess at the very week the app
    /// then overrules it on: `AnalysisReportValidator` forces a recovery card at
    /// six of seven days whatever the model wrote, and a reason written against
    /// the wrong week reads as an invention.
    ///
    /// The session split is stated so the reason can name what filled the week,
    /// but the day count — the figure the rule turns on — is the union: one day
    /// carrying a run and a squat session is one training day.
    ///
    /// The mean heart rate is `RecoveryMetrics.meanHeartRate(in:)` over the same
    /// seven days, i.e. **the figure the recovery card prints as "Avg HR"** —
    /// not the endurance section's "Mean heart rate", which covers the whole
    /// window and only the endurance half. Without it the model could cite the
    /// window mean in a reason that appears directly above a label showing the
    /// week's. Omitted where nothing in the week recorded one (US-15 AC7).
    private static func lastSevenDaysLine(
        strength: [WorkoutSummary],
        endurance: [WorkoutSummary],
        now: Date,
        calendar: Calendar
    ) -> String {
        let start = AnalysisWindow.weekStart(0, endingAt: now, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        func inWeek(_ summaries: [WorkoutSummary]) -> [WorkoutSummary] {
            summaries.filter { $0.startTime >= start && $0.startTime < end }
        }

        let recentStrength = inWeek(strength)
        let recentEndurance = inWeek(endurance)
        let days = PromptFigures.trainingDayStarts(recentStrength, calendar: calendar)
            .union(PromptFigures.trainingDayStarts(recentEndurance, calendar: calendar))
        var line = "Last 7 days: \(CountFormatter.labelled(days.count, singular: "training day")) "
            + "(\(CountFormatter.labelled(recentStrength.count, singular: "strength session")), "
            + "\(CountFormatter.labelled(recentEndurance.count, singular: "endurance session")))"
        if let heartRate = RecoveryMetrics.meanHeartRate(in: recentStrength + recentEndurance) {
            line += ", mean heart rate \(heartRate) bpm"
        }
        return line
    }

    /// The longest run of consecutive training days in the window, with the
    /// dates it ran over.
    ///
    /// Consecutive days rather than "hard" days in any qualitative sense:
    /// FitBuddy measures no intensity it could rank sessions by, and calling a
    /// day hard on a figure it does not have would be the kind of invention
    /// the ground rules forbid. What it can state is that six days in a row
    /// carried training, which is what US-3 AC6 already turns into a recovery
    /// hint (#184).
    private static func longestStreakLine(
        _ trainingDays: Set<Date>,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String? {
        let sorted = trainingDays.sorted()
        guard let first = sorted.first else { return nil }

        var best = (start: first, end: first, length: 1)
        var current = best
        for day in sorted.dropFirst() {
            let next = calendar.date(byAdding: .day, value: 1, to: current.end)
            if let next, calendar.isDate(day, inSameDayAs: next) {
                current = (current.start, day, current.length + 1)
            } else {
                current = (day, day, 1)
            }
            if current.length > best.length { best = current }
        }

        let counted = CountFormatter.labelled(best.length, singular: "day")
        guard best.length > 1 else {
            return "Longest streak of consecutive training days: \(counted) "
                + "(\(formatter.string(best.start)))"
        }
        return "Longest streak of consecutive training days: \(counted) "
            + "(\(formatter.string(best.start)) to \(formatter.string(best.end)))"
    }
}

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
/// Only rendered when the window holds **both** domains. With one domain the
/// section would restate the "Training days" line of that domain's own header
/// and nothing else — and a Hevy-only cache has to produce exactly the prompt
/// it produced before the split (#183 AC1). #184 revisits this as it takes
/// recovery across all sources.
enum LoadPromptSection {
    /// The week-structure section, or `nil` when one of the two domains is
    /// empty.
    static func section(
        strength: [WorkoutSummary],
        endurance: [WorkoutSummary],
        window: AnalysisWindow,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String? {
        guard !strength.isEmpty, !endurance.isEmpty else { return nil }

        let strengthDays = PromptFigures.trainingDayStarts(strength, calendar: calendar)
        let enduranceDays = PromptFigures.trainingDayStarts(endurance, calendar: calendar)
        let trainingDays = strengthDays.union(enduranceDays)
        let both = strengthDays.intersection(enduranceDays)

        var lines = [
            "## Week structure (last \(window.weeks) weeks)",
            "Training days: \(trainingDays.count) of \(window.days) "
                + "(\(PromptFigures.frequency(trainingDays.count, window: window)) per week)",
            "Days with strength only: \(strengthDays.subtracting(enduranceDays).count)",
            "Days with endurance only: \(enduranceDays.subtracting(strengthDays).count)",
            "Days with both: \(both.count)",
            "Rest days: \(max(0, window.days - trainingDays.count))",
        ]
        if let streak = longestStreakLine(trainingDays, calendar: calendar, days: formatter) {
            lines.append(streak)
        }
        return lines.joined(separator: "\n")
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

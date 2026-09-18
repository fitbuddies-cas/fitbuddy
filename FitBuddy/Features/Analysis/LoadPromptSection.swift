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
/// Only rendered when the **window** holds both domains. With one domain the
/// section would restate the "Training days" line of that domain's own header
/// and nothing else — and a Hevy-only cache has to produce exactly the prompt
/// it produced before the split (#183 AC1). #184 added the last-seven-days
/// line inside that gate.
///
/// Since #185 the *profile* decides which of two forms the section takes,
/// while the window keeps deciding whether there is one at all:
///
/// - **Overall load** — the full structure: the days each domain filled, the
///   days carrying both, the longest streak and the last seven days.
/// - **Strength or Endurance, with the other domain in the window** — the
///   last seven days and nothing else, prefaced by the reason.
/// - **A single-domain window** — `nil`, as before: nothing was left out, and
///   that domain's own header already states its training days.
///
/// **The orchestrator's decision (#184's open question, settled here): a run
/// still counts as a training day for the recovery rule under the "Strength"
/// profile.** One body has one recovery, and FitBuddy records no intensity by
/// which a run could be ranked below a squat session — so leaving endurance
/// out of the analysis is a choice about what to advise on, never a claim that
/// the week was emptier than it was. `RecoveryMetrics` counts every session
/// whatever the profile, `AnalysisReportValidator` enforces the card on that
/// count (US-3 AC6 / US-15 AC3), and a prompt that stayed silent would have
/// the model reason about a week the app then overrules it on.
enum LoadPromptSection {
    /// The week-structure section, or `nil` when the window holds only one
    /// domain.
    ///
    /// - Parameters:
    ///   - strength: Every strength session of the window, whatever the
    ///     profile covers — recovery is judged over all of it (#185).
    ///   - endurance: Every endurance session of the window, likewise.
    ///   - profile: What the user asked this analysis to be about. Decides
    ///     which of the two forms above is rendered.
    ///   - now: The reference the window ends at, for the last-seven-days line
    ///     (#184).
    static func section(
        strength: [WorkoutSummary],
        endurance: [WorkoutSummary],
        profile: AnalysisProfile = .overallLoad,
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String? {
        guard !strength.isEmpty, !endurance.isEmpty else { return nil }
        guard profile.coversBothDomains else {
            return recoverySection(
                strength: strength,
                endurance: endurance,
                profile: profile,
                window: window,
                now: now,
                calendar: calendar
            )
        }

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
        lines.append(
            lastSevenDaysLine(strength: strength, endurance: endurance, now: now, calendar: calendar)
        )
        return lines.joined(separator: "\n")
    }

    /// The week structure reduced to what a single-domain profile still has
    /// to be told: the week the recovery rule is judged on (#185).
    ///
    /// The other domain's sessions are described nowhere else in this prompt,
    /// so the day count below would look like an error without the sentence
    /// that explains it — the model, told six training days and shown three
    /// strength sessions, would otherwise assume a figure had gone wrong.
    private static func recoverySection(
        strength: [WorkoutSummary],
        endurance: [WorkoutSummary],
        profile: AnalysisProfile,
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar
    ) -> String {
        let left = AnalysisDomain.allCases
            .filter { !profile.covers($0) }
            .map(\.displayName)
            .joined(separator: " and ")
        return [
            "## Week structure (last \(window.weeks) weeks)",
            "I asked about my \(profile.displayName.lowercased()) training only, so my "
                + "\(left) sessions are not described above. They happened in the same "
                + "weeks and cost the same recovery, so the day count below counts them too.",
            lastSevenDaysLine(
                strength: strength,
                endurance: endurance,
                now: now,
                calendar: calendar
            ),
        ].joined(separator: "\n")
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
        return "Last 7 days: \(CountFormatter.labelled(days.count, singular: "training day")) "
            + "(\(CountFormatter.labelled(recentStrength.count, singular: "strength session")), "
            + "\(CountFormatter.labelled(recentEndurance.count, singular: "endurance session")))"
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

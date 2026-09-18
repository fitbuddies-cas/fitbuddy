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
/// What is rendered depends on what the window holds and on what the user's
/// `AnalysisProfile` asked about (#185):
///
/// - **Both domains, "Overall load":** the full section — the cross-domain day
///   counts, the streak and the last seven days.
/// - **Endurance only:** the streak and the last seven days. The window's own
///   training days are already in the endurance header, and "Days with strength
///   only: 0" restates the absence of a section the model was told not to
///   reason about.
/// - **Both domains, one of them left out by the profile:** the last seven days
///   and nothing else, prefaced by the reason. Everything above that line would
///   describe training this prompt does not carry.
/// - **Strength only:** `nil`, unchanged (#183 AC1).
///
/// **The orchestrator's decision (#184's open question, settled here): a run
/// still counts as a training day for the recovery rule under the "Strength"
/// profile.** One body has one recovery, and FitBuddy records no intensity by
/// which a run could be ranked below a squat session — so leaving endurance out
/// of the analysis is a choice about what to advise on, never a claim that the
/// week was emptier than it was. `RecoveryMetrics` counts every session whatever
/// the profile, `AnalysisReportValidator` enforces the card on that count (US-3
/// AC6 / US-15 AC3), and a prompt that stayed silent would have the model reason
/// about a week the app then overrules it on.
enum LoadPromptSection {
    /// The week-structure section, or `nil` when the window holds no endurance
    /// session.
    ///
    /// - Parameters:
    ///   - strength: Every strength session of the window, whatever the
    ///     profile covers — recovery is judged over all of it (#185).
    ///   - endurance: Every endurance session of the window, likewise.
    ///   - profile: What the user asked this analysis to be about. Decides
    ///     which of the forms above is rendered.
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
        guard !endurance.isEmpty else { return nil }
        // A profile that leaves out a domain this window holds gets the
        // recovery week and nothing else: the figures above it describe
        // training the prompt does not carry.
        if omitsAPresentDomain(profile, strength: strength, endurance: endurance) {
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

    /// Whether the profile leaves out a domain this window actually holds.
    ///
    /// The distinction that decides which form the section takes: an
    /// endurance-only window under the "Endurance" profile omits nothing, and
    /// gets the ordinary section #184 built for it, while the same profile over
    /// a window that also held lifts has to say why they are missing.
    private static func omitsAPresentDomain(
        _ profile: AnalysisProfile,
        strength: [WorkoutSummary],
        endurance: [WorkoutSummary]
    ) -> Bool {
        (!profile.covers(.strength) && !strength.isEmpty)
            || (!profile.covers(.endurance) && !endurance.isEmpty)
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
        if let heartRate = RecoveryMetrics.meanHeartRate(in: recentStrength + recentEndurance),
           let figure = PromptFigures.heartRate(heartRate) {
            line += ", mean heart rate \(figure)"
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

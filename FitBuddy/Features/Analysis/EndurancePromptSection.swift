import Foundation

/// The endurance half of the prompt: weekly kilometres and hours, heart rate,
/// pace and the same comparison window the strength half gets (US-15 AC2,
/// #183).
///
/// Before this, `AnalysisPromptBuilder` threw every endurance session away.
/// That was the right call while the system prompt described strength work
/// alone — rule 5 reads a 0 kg line as bodyweight or timed work, so a run
/// passed through as a session would have told a runner about a volume
/// collapse that never happened. The fix is not to drop the filter but to give
/// the model the figures that describe endurance work and the rules that go
/// with them.
///
/// Every line is omitted when its figure was not recorded (US-15 AC7): a
/// treadmill session without a strap has no heart rate, an indoor ride has no
/// distance, and a placeholder would read to the model as a measured zero.
enum EndurancePromptSection {
    /// The endurance sections, in prompt order — empty when the window holds
    /// no endurance session, so a Hevy-only cache produces the prompt it
    /// always produced (#183 AC1).
    ///
    /// - Parameters:
    ///   - recent: Endurance sessions of the analysed window.
    ///   - previous: Endurance sessions of the equally long window before it.
    static func sections(
        recent: [WorkoutSummary],
        previous: [WorkoutSummary],
        window: AnalysisWindow,
        recentStart: Date,
        previousStart: Date,
        now: Date,
        calendar: Calendar,
        days: PromptDayFormatter
    ) -> [String] {
        guard !recent.isEmpty else { return [] }
        return [
            windowSection(recent, window: window, from: recentStart, to: now, calendar: calendar, days: days),
            weeklySection(recent, window: window, now: now, calendar: calendar, days: days),
            comparisonSection(
                previous,
                window: window,
                from: previousStart,
                to: recentStart,
                calendar: calendar,
                days: days
            ),
        ]
    }

    // MARK: - Window

    private static func windowSection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String {
        let trainingDays = PromptFigures.trainingDays(summaries, calendar: calendar)
        var lines = [
            "## Endurance, last \(window.weeks) weeks "
                + "(\(formatter.string(start)) to \(formatter.string(end)))",
            "Sessions: \(summaries.count)",
            "Training days: \(trainingDays) "
                + "(\(PromptFigures.frequency(trainingDays, window: window)) per week)",
        ]
        if let distance = PromptFigures.distance(PromptFigures.distance(of: summaries)) {
            lines.append("Total distance: \(distance)")
        }
        if let time = PromptFigures.duration(PromptFigures.duration(of: summaries)) {
            lines.append("Total time: \(time)")
        }
        if let heartRate = meanHeartRateLine(summaries) {
            lines.append(heartRate)
        }
        lines.append(contentsOf: longestSessionLines(summaries, days: formatter))
        let sports = sportRows(summaries)
        if !sports.isEmpty {
            lines.append("By sport:")
            lines.append(contentsOf: sports)
        }
        return lines.joined(separator: "\n")
    }

    /// The mean over the sessions that recorded a heart rate, saying how many
    /// did when that is not all of them.
    ///
    /// "Mean", never "average": US-3 AC3 forbids population comparisons, and
    /// the word "average" in a prompt is one reading away from one. The RPE
    /// line of the Exercises section spells it the same way.
    private static func meanHeartRateLine(_ summaries: [WorkoutSummary]) -> String? {
        let recorded = summaries.filter { ($0.cardio?.averageHeartRate ?? 0) > 0 }
        guard let mean = meanHeartRate(of: summaries), let text = PromptFigures.heartRate(mean)
        else { return nil }
        guard recorded.count < summaries.count else { return "Mean heart rate: \(text)" }
        let counted = CountFormatter.labelled(recorded.count, singular: "session")
        return "Mean heart rate: \(text) (over the \(counted) that recorded one)"
    }

    /// The longest session of the window — the one figure the totals cannot
    /// carry, and the one a long-run recommendation starts from.
    ///
    /// Two lines where the longest by distance and the longest by time are
    /// different sessions, one where they are the same. Ranking by distance
    /// alone hid every duration-only session as soon as a single session
    /// carried a distance: a 2 h indoor ride next to a 10 km run is the longer
    /// effort of the two and simply disappeared from the prompt.
    private static func longestSessionLines(
        _ summaries: [WorkoutSummary],
        days: PromptDayFormatter
    ) -> [String] {
        let byDistance = summaries
            .filter { ($0.distanceMeters ?? 0) > 0 }
            .max { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
        let byTime = summaries
            .filter { ($0.durationSeconds ?? 0) > 0 }
            .max { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }

        if let byDistance, let byTime, byDistance.id != byTime.id {
            return [
                "Longest session by distance: \(describe(byDistance, days: days))",
                "Longest session by time: \(describe(byTime, days: days))",
            ]
        }
        guard let session = byDistance ?? byTime else { return [] }
        return ["Longest session: \(describe(session, days: days))"]
    }

    /// One session as the figures it recorded, its date and its title.
    private static func describe(_ session: WorkoutSummary, days: PromptDayFormatter) -> String {
        let figures = [
            session.distanceMeters.flatMap(PromptFigures.distance),
            session.durationSeconds.flatMap(PromptFigures.duration),
        ].compactMap { $0 }
        return "\(figures.joined(separator: ", ")) "
            + "on \(days.string(session.startTime)) (\(session.title))"
    }

    /// One row per sport the window held, so "nine sessions" cannot read as
    /// nine runs when it was five runs, three rides and a swim (#180).
    ///
    /// Rides are stated in km/h and everything else in min/km: a pace per
    /// kilometre is what a runner reads and a speed is what a cyclist reads,
    /// and the wrong one is a figure the model would have to convert before it
    /// could say anything about it.
    ///
    /// A row carrying nothing but its session count is kept: it says *which*
    /// sports were trained, which the "Sessions:" line above cannot.
    private static func sportRows(_ summaries: [WorkoutSummary]) -> [String] {
        Sport.allCases.compactMap { sport in
            let inSport = summaries.filter { Sport(kind: $0.kind) == sport }
            guard !inSport.isEmpty else { return nil }

            let meters = PromptFigures.distance(of: inSport)
            let seconds = PromptFigures.duration(of: inSport)
            var parts = [CountFormatter.labelled(inSport.count, singular: "session")]
            if let distance = PromptFigures.distance(meters) { parts.append(distance) }
            if let time = PromptFigures.duration(seconds) { parts.append(time) }
            if let speed = meanSpeed(of: inSport) {
                let text = sport == .ride
                    ? PromptFigures.speed(metersPerSecond: speed).map { "mean speed \($0)" }
                    : PromptFigures.pace(metersPerSecond: speed).map { "mean pace \($0)" }
                if let text { parts.append(text) }
            }
            if let rate = meanHeartRate(of: inSport), let text = PromptFigures.heartRate(rate) {
                parts.append("mean heart rate \(text)")
            }
            return "- \(sport.displayName): \(parts.joined(separator: ", "))"
        }
    }

    /// The mean of the heart rates the sessions recorded, or `nil` when none
    /// did.
    private static func meanHeartRate(of summaries: [WorkoutSummary]) -> Int? {
        let rates = summaries.compactMap { $0.cardio?.averageHeartRate }.filter { $0 > 0 }
        guard !rates.isEmpty else { return nil }
        return Int((Double(rates.reduce(0, +)) / Double(rates.count)).rounded())
    }

    /// The sport's mean speed in m/s: distance over time across the sessions
    /// that recorded **both**, falling back to the mean of the speeds the
    /// source reported.
    ///
    /// Only the sessions that recorded both, because the row's own totals are
    /// no safe numerator and denominator: a 10 km run in 50 min next to a
    /// 60 min treadmill session with no distance would divide 10 km by 110 min
    /// and state a mean pace of 11:00 min/km for a runner holding 5:00. The
    /// totals still describe the sport truthfully; the ratio between them does
    /// not.
    ///
    /// Distance over time is preferred over the reported speeds because it is
    /// the figure the two lines before it state — a pace derived from
    /// something else would contradict them in a prompt that has no room to
    /// explain why.
    private static func meanSpeed(of summaries: [WorkoutSummary]) -> Double? {
        let paired = summaries.filter { ($0.distanceMeters ?? 0) > 0 && ($0.durationSeconds ?? 0) > 0 }
        let meters = PromptFigures.distance(of: paired)
        let seconds = PromptFigures.duration(of: paired)
        if meters > 0, seconds > 0 { return meters / Double(seconds) }
        let speeds = summaries
            .compactMap { $0.cardio?.averageSpeedMetersPerSecond }
            .filter { $0.isFinite && $0 > 0 }
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    // MARK: - Per week

    /// Per-week distance and time, newest first — the same shape the strength
    /// half uses, and for the same reason: four weeks of 20 km and one week of
    /// 80 km justify opposite recommendations.
    private static func weeklySection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        now: Date,
        calendar: Calendar,
        days: PromptDayFormatter
    ) -> String {
        let weeks = (0..<window.weeks).map { index -> String in
            let start = AnalysisWindow.weekStart(index, endingAt: now, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let inWeek = summaries.filter { $0.startTime >= start && $0.startTime < end }
            let label = index == 0 ? "most recent" : "\(index + 1) weeks back"
            var parts = ["\(inWeek.count) sessions"]
            if let distance = PromptFigures.distance(PromptFigures.distance(of: inWeek)) {
                parts.append(distance)
            }
            if let time = PromptFigures.duration(PromptFigures.duration(of: inWeek)) {
                parts.append(time)
            }
            return "- Week starting \(days.string(start)) (\(label)): \(parts.joined(separator: ", "))"
        }
        return (["## Endurance per week"] + weeks).joined(separator: "\n")
    }

    // MARK: - Comparison

    private static func comparisonSection(
        _ summaries: [WorkoutSummary],
        window: AnalysisWindow,
        from start: Date,
        to end: Date,
        calendar: Calendar,
        days formatter: PromptDayFormatter
    ) -> String {
        let header = "## Previous \(window.weeks) weeks "
            + "(\(formatter.string(start)) to \(formatter.string(end))), endurance, for comparison"
        guard !summaries.isEmpty else {
            return header + "\nNo endurance sessions recorded. This may be a break, or simply "
                + "the start of the recorded history — do not assume which."
        }

        let trainingDays = PromptFigures.trainingDays(summaries, calendar: calendar)
        var lines = [
            header,
            "Sessions: \(summaries.count)",
            "Training days: \(trainingDays) "
                + "(\(PromptFigures.frequency(trainingDays, window: window)) per week)",
        ]
        if let distance = PromptFigures.distance(PromptFigures.distance(of: summaries)) {
            lines.append("Total distance: \(distance)")
        }
        if let time = PromptFigures.duration(PromptFigures.duration(of: summaries)) {
            lines.append("Total time: \(time)")
        }
        return lines.joined(separator: "\n")
    }

    /// The sports this section groups by — `ActivityKind`'s endurance cases,
    /// with everything else collected under "Other".
    ///
    /// A session can reach this section with a non-endurance `kind`: a Hevy
    /// workout of treadmill sets carries the model's default `.strength` and
    /// is endurance by `WorkoutSummary.isCardio`'s fallback heuristic
    /// (ADR-012), and a row cached before schema V5 reads as `.other`.
    /// Filing either under "Strength" inside the endurance section would be
    /// worse than saying "Other", which is exactly what is known about it.
    private enum Sport: CaseIterable {
        case run, ride, swim, hike, walk, other

        init(kind: ActivityKind) {
            switch kind {
            case .run: self = .run
            case .ride: self = .ride
            case .swim: self = .swim
            case .hike: self = .hike
            case .walk: self = .walk
            case .strength, .other: self = .other
            }
        }

        var displayName: String {
            switch self {
            case .run: return "Run"
            case .ride: return "Ride"
            case .swim: return "Swim"
            case .hike: return "Hike"
            case .walk: return "Walk"
            case .other: return "Other"
            }
        }
    }
}

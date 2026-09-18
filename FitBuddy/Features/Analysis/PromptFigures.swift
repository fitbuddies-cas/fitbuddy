import Foundation

/// Every figure the prompt states, written the same way in every section
/// (#183).
///
/// Locale-free throughout. `VolumeFormatter`, `DistanceFormatter` and their
/// siblings in `Core/DesignSystem` follow the device locale — which would put
/// `48'320` in front of the model on a Swiss device and `48,320` on a US one,
/// for identical training. A prompt has no reader to charm; it needs one
/// unambiguous form, and two prompts built from the same cache must be the
/// same string.
///
/// **The word "mean", never "average".** US-3 AC3 forbids population
/// comparisons, and `AnalysisPromptBuilderTests` enforces it by asserting that
/// the user turn does not contain the substring "average" at all. A mean over
/// this user's own sessions is exactly what the prompt may state, so it is
/// spelled the way the existing RPE line already spells it.
///
/// **Unified with #181 in #186, as that comment promised.** Every endurance
/// figure below is now one call into `DistanceFormatter.plain`,
/// `PaceFormatter.plain`, `HeartRateFormatter.plain` or
/// `WorkoutDurationFormatter.seconds`, so the ranges are decided in
/// `Core/DesignSystem` once and a card and the prompt behind it cannot state
/// the same session differently. What stays here is the part that is about the
/// *prompt* rather than about a unit: the `nil` at a figure nothing recorded
/// (AC7 — the prompt leaves the line out, where a formatter would print
/// `"0 km"`), the aggregation helpers, and `speed`, which has no display
/// counterpart because no screen shows a ride in km/h yet.
enum PromptFigures {
    // MARK: - Strength

    /// Volume, without grouping separators.
    static func kg(_ kilograms: Double) -> String {
        "\(Int(kilograms.rounded())) kg"
    }

    /// A 1RM change with its direction spelled out.
    static func signed(_ kilograms: Double) -> String {
        let text = PlainWeightFormatter.string(abs(kilograms), decimals: 1)
        guard text != "0" else { return "no change" }
        return (kilograms > 0 ? "+" : "-") + text + " kg"
    }

    // MARK: - Endurance

    /// A distance in metres, as the unit a training log states it in: whole
    /// metres below a kilometre, one decimal up to 100 km, whole kilometres
    /// above it.
    ///
    /// `nil` for zero, negative and non-finite input — there is no cell to
    /// print then, and AC7 wants it left out rather than filled with a
    /// placeholder.
    static func distance(_ meters: Double) -> String? {
        guard meters.isFinite, meters > 0 else { return nil }
        return DistanceFormatter.plain(meters)
    }

    /// A duration in seconds as hours and minutes: `45 min`, `1 h`,
    /// `9 h 10 min`.
    ///
    /// Hours are never rolled into days — a four-week endurance total reads
    /// `26 h 30 min`, which is how a training log states it. `nil` at zero and
    /// below, for the same reason `distance` returns `nil` there.
    ///
    /// `WorkoutDurationFormatter.seconds` decides the form, as the detail
    /// header and the endurance cards do (#186). Two consequences of the one
    /// rule, both deliberate: the seconds are **truncated** rather than
    /// rounded to a minute — a watch shows `1 h 29 min` for 1:29:40, and a
    /// prompt that rounded it up would state a minute the card below it does
    /// not — and a session shorter than a minute reads `< 1 min` rather than
    /// disappearing from the section.
    static func duration(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        return WorkoutDurationFormatter.seconds(TimeInterval(seconds))
    }

    /// Pace per kilometre in `M:SS min/km`, the form a runner reads.
    ///
    /// `nil` at or below zero, for a non-finite speed, and past `99:59` —
    /// a GPS artefact rather than a pace, and a figure the model would have to
    /// explain.
    static func pace(metersPerSecond: Double) -> String? {
        PaceFormatter.plain(metersPerSecond: metersPerSecond)
    }

    /// Speed in `km/h` — what a ride is read in, where a pace per kilometre
    /// says the same thing in a unit nobody uses for it.
    static func speed(metersPerSecond: Double) -> String? {
        guard metersPerSecond.isFinite, metersPerSecond > 0 else { return nil }
        return "\(PlainWeightFormatter.string(metersPerSecond * 3.6, decimals: 1)) km/h"
    }

    /// A heart rate in beats per minute. `nil` at or below zero — a rate
    /// nobody recorded is left out of the section, where
    /// `HeartRateFormatter.plain` would print `"0 bpm"` (AC7).
    static func heartRate(_ beatsPerMinute: Int) -> String? {
        guard beatsPerMinute > 0 else { return nil }
        return HeartRateFormatter.plain(Double(beatsPerMinute))
    }

    // MARK: - Aggregation

    static func volume(of summaries: [WorkoutSummary]) -> Double {
        summaries.reduce(0) { $0 + $1.volumeKg }
    }

    static func distance(of summaries: [WorkoutSummary]) -> Double {
        summaries.compactMap(\.distanceMeters).reduce(0, +)
    }

    static func duration(of summaries: [WorkoutSummary]) -> Int {
        summaries.compactMap(\.durationSeconds).reduce(0, +)
    }

    /// Calendar days carrying at least one session — two sessions on one day
    /// are one training day.
    static func trainingDayStarts(_ summaries: [WorkoutSummary], calendar: Calendar) -> Set<Date> {
        Set(summaries.map { calendar.startOfDay(for: $0.startTime) })
    }

    static func trainingDays(_ summaries: [WorkoutSummary], calendar: Calendar) -> Int {
        trainingDayStarts(summaries, calendar: calendar).count
    }

    static func frequency(_ trainingDays: Int, window: AnalysisWindow) -> String {
        let perWeek = Double(trainingDays) / Double(window.weeks)
        return String(format: "%.1f days", perWeek)
    }
}

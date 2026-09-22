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
/// > **#186 will unify this with #181.** That branch adds `DistanceFormatter`,
/// > `PaceFormatter`, `HeartRateFormatter` and `WorkoutDurationFormatter`,
/// > each with a locale-free `plain(_:)` variant that says the same thing as
/// > the functions here. #181 is not in this branch's base, so nothing was
/// > copied from it; when both have landed, the bodies below become calls into
/// > those `plain` variants and the ranges are decided in one place.
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
        let kilometers = meters / 1_000
        // Rounded at the precision it is printed with, so the threshold and
        // the printed value cannot disagree (999.6 m is 1 km, never 1000 m).
        if PlainWeightFormatter.rounded(kilometers, decimals: 1) < 1 {
            return "\(Int(meters.rounded())) m"
        }
        if kilometers.rounded() >= 100 {
            return "\(Int(kilometers.rounded())) km"
        }
        return "\(PlainWeightFormatter.string(kilometers, decimals: 1)) km"
    }

    /// A duration in seconds as hours and minutes: `45 min`, `1 h`,
    /// `9 h 10 min`.
    ///
    /// Hours are never rolled into days — a four-week endurance total reads
    /// `26 h 30 min`, which is how a training log states it. `nil` below half
    /// a minute, for the same reason `distance` returns `nil` at zero.
    static func duration(_ seconds: Int) -> String? {
        guard seconds > 0 else { return nil }
        let minutes = Int((Double(seconds) / 60).rounded())
        guard minutes > 0 else { return nil }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) min" }
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    /// Pace per kilometre in `M:SS min/km`, the form a runner reads.
    ///
    /// `nil` at or below zero, for a non-finite speed, and past `99:59` —
    /// a GPS artefact rather than a pace, and a figure the model would have to
    /// explain.
    static func pace(metersPerSecond: Double) -> String? {
        guard metersPerSecond.isFinite, metersPerSecond > 0 else { return nil }
        let secondsPerKilometer = 1_000 / metersPerSecond
        // Bounded as a `Double` before the `Int` conversion: a speed of
        // 1e-20 m/s overflows `Int` on the way in.
        guard secondsPerKilometer <= 5_999 else { return nil }
        let total = Int(secondsPerKilometer.rounded())
        return String(format: "%d:%02d min/km", total / 60, total % 60)
    }

    /// Speed in `km/h` — what a ride is read in, where a pace per kilometre
    /// says the same thing in a unit nobody uses for it.
    static func speed(metersPerSecond: Double) -> String? {
        guard metersPerSecond.isFinite, metersPerSecond > 0 else { return nil }
        return "\(PlainWeightFormatter.string(metersPerSecond * 3.6, decimals: 1)) km/h"
    }

    /// A heart rate in beats per minute. `nil` at or below zero.
    static func heartRate(_ beatsPerMinute: Int) -> String? {
        guard beatsPerMinute > 0 else { return nil }
        return "\(beatsPerMinute) bpm"
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

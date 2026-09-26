import Foundation

/// How often each muscle group was trained per week in the analysed window
/// (US-3 AC8, US-14, #175).
///
/// The prompt's Muscle groups section states these figures, and an imbalance
/// card is only kept when its per-week figures match them — so both read the
/// count and the rounding from here, the way the working weight is shared
/// through `WorkingSet`.
enum MuscleGroupFrequency {
    /// Decimals a per-week figure keeps: `0.8`, `2.5`. The prompt writes the
    /// figure at this precision, so a card can only be expected to match it at
    /// this precision.
    static let decimals = 1

    /// Sessions per week that loaded each group, rounded to `decimals`.
    ///
    /// A session counts once per group it holds at least one counted set for,
    /// however many exercises of that group it contained: two chest exercises
    /// in one session are one chest session. Divided by the window's full
    /// length, like the training-day average, so a break inside the window
    /// lowers the figure. Groups never trained are absent, which reads as 0.
    ///
    /// - Parameters:
    ///   - sessions: The strength sessions of the analysed window —
    ///     `AnalysisPromptBuilder.sessions(in:for:)` with `.strength`, already restricted to
    ///     the window.
    ///   - window: The window analysed; its length is the divisor.
    static func sessionsPerWeek(
        in sessions: [WorkoutSummary],
        window: AnalysisWindow
    ) -> [MuscleGroup: Double] {
        sessionCounts(in: sessions).mapValues { count in
            PlainWeightFormatter.rounded(Double(count) / Double(window.weeks), decimals: decimals)
        }
    }

    /// Sessions that loaded each group, unrounded.
    static func sessionCounts(in sessions: [WorkoutSummary]) -> [MuscleGroup: Int] {
        var counts: [MuscleGroup: Int] = [:]
        for session in sessions {
            // A set count of zero is a group made of warm-ups only — not
            // trained, the same filter `MuscleLoad.merged` applies.
            let groups = Set(session.muscleLoads.filter { $0.setCount > 0 }.map(\.group))
            for group in groups {
                counts[group, default: 0] += 1
            }
        }
        return counts
    }

    /// A per-week figure as the prompt writes it: `0.8`, `3`.
    static func string(_ perWeek: Double) -> String {
        PlainWeightFormatter.string(perWeek, decimals: decimals)
    }
}

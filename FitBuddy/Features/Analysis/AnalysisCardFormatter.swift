import Foundation

/// The figures and derived sentences of the report cards (US-14, #177).
///
/// Everything a card view prints that is not the model's own text comes from
/// here, so the views only lay values out and the wording can be tested
/// without rendering.
enum AnalysisCardFormatter {
    /// `62.5` → `"62.5 kg"`, `60` → `"60 kg"`, `61.25` → `"61.25 kg"`.
    ///
    /// Two decimals at most, unlike `OneRepMaxFormatter`/`SetMetricFormatter`:
    /// a progression is a plate step, and plates come in 1.25 kg pairs — one
    /// decimal would print `61.3 kg`, a weight nobody can load, and a delta of
    /// `+1.3 kg`. Locale-aware like those formatters, since this is display
    /// text; trailing zeros are dropped.
    ///
    /// Rounded half away from zero by `PlainWeightFormatter` before it is
    /// formatted, the same rule `delta` rounds by: `62.125` reads `62.13 kg`
    /// next to `+2.13 kg`, not `62.12 kg` under Foundation's half-even rule.
    static func weight(_ kilograms: Double, locale: Locale = .current) -> String {
        number(PlainWeightFormatter.rounded(kilograms), decimals: 0...2, locale: locale) + " kg"
    }

    /// The signed step from `fromKg` to `toKg`: `"+2.5 kg"`, `"−1.25 kg"`.
    ///
    /// The difference is rounded to the displayed precision first, so floating
    /// point noise (`62.5 - 60.1`) cannot print as `2.4` next to weights that
    /// read `60.1` and `62.5`.
    static func delta(fromKg: Double, toKg: Double, locale: Locale = .current) -> String {
        let step = PlainWeightFormatter.rounded(toKg - fromKg)
        let sign = step < 0 ? "\u{2212}" : "+"
        return "\(sign)\(number(abs(step), decimals: 0...2, locale: locale)) kg"
    }

    /// A per-week frequency: `3`, `0.8` — at the precision the prompt stated
    /// it (`MuscleGroupFrequency.decimals`), so the card and the model's
    /// reasoning never disagree about the number. Unlike the prompt, written
    /// with the locale's separator, like the weights on the same screen.
    static func frequency(_ perWeek: Double, locale: Locale = .current) -> String {
        let decimals = MuscleGroupFrequency.decimals
        return number(
            PlainWeightFormatter.rounded(perWeek, decimals: decimals),
            decimals: 0...decimals,
            locale: locale
        )
    }

    /// A per-week frequency as the imbalance card labels it: `"3×/wk"`,
    /// `"0.8×/wk"`.
    static func perWeek(_ perWeek: Double, locale: Locale = .current) -> String {
        "\(frequency(perWeek, locale: locale))×/wk"
    }

    /// `"Chest vs Legs"` — the imbalance card's header.
    static func imbalanceTitle(_ bars: [ImbalanceBar]) -> String {
        bars.map(\.group.displayName).joined(separator: " vs ")
    }

    /// `"You're training chest 3×/week but legs only 1×/week."` — the
    /// imbalance card's headline, built from the app's figures, never the
    /// model's. Expects the bars as `ImbalanceBar.bars` orders them, the more
    /// frequent group first.
    static func imbalanceHeadline(_ bars: [ImbalanceBar], locale: Locale = .current) -> String {
        guard bars.count == 2 else { return imbalanceTitle(bars) }
        let high = bars[0]
        let low = bars[1]
        return """
        You're training \(high.group.displayName.lowercased()) \
        \(frequency(high.perWeek, locale: locale))×/week but \
        \(low.group.displayName.lowercased()) only \
        \(frequency(low.perWeek, locale: locale))×/week.
        """
    }

    /// `"You trained 6 of the last 7 days."` — the recovery card's headline,
    /// from the app's own count (US-3 AC6).
    ///
    /// Since #184 the count spans strength and endurance, and the sentence
    /// needed no rewording for it: "trained" was never a claim about barbells.
    static func recoveryHeadline(_ metrics: RecoveryMetrics) -> String {
        "You trained \(metrics.trainingDays) of the last 7 days."
    }

    /// `8.25` → `"8.3"`: one decimal, as the design shows it, rounded half
    /// away from zero like the weights.
    static func rpe(_ rpe: Double, locale: Locale = .current) -> String {
        number(PlainWeightFormatter.rounded(rpe, decimals: 1), decimals: 1...1, locale: locale)
    }

    /// `48` → `"48 h"`.
    static func rest(hours: Int) -> String {
        "\(hours) h"
    }

    // MARK: - Rep progression card (#234)

    /// `8` → `"8 reps"`, `1` → `"1 rep"`.
    static func reps(_ reps: Int) -> String {
        "\(reps) \(reps == 1 ? "rep" : "reps")"
    }

    /// The signed step from `fromReps` to `toReps`: `"+2 reps"`, `"+1 rep"`.
    static func repDelta(fromReps: Int, toReps: Int) -> String {
        let step = toReps - fromReps
        let sign = step < 0 ? "\u{2212}" : "+"
        return "\(sign)\(reps(abs(step)))"
    }

    /// `"at 22.5 kg"` — the weight a rep progression holds.
    static func atWeight(_ kilograms: Double, locale: Locale = .current) -> String {
        "at \(weight(kilograms, locale: locale))"
    }

    // MARK: - Metric card (#186)

    /// The chip title of a metric card: `"Increase"`, `"Reduce"`, `"Faster"`,
    /// `"Easier"`.
    ///
    /// The **title follows the number**, the colour follows the meaning — the
    /// two are separate on purpose (#186 asks colour to follow the meaning).
    /// "Reduce" over a pace would read as a step backwards, so a lower-is-
    /// better unit gets its own pair of words for the same two directions.
    static func metricChipTitle(from: Double, to: Double, unit: MetricUnit) -> String {
        if unit.isLowerBetter {
            return to < from ? "Faster" : "Easier"
        }
        return to > from ? "Increase" : "Reduce"
    }

    /// `"arrow.up"` or `"arrow.down"` — the direction of the figure, not of
    /// the judgement.
    static func metricChipSymbol(from: Double, to: Double) -> String {
        to < from ? "arrow.down" : "arrow.up"
    }

    // MARK: - Interference card (#186)

    /// `"Strength and endurance shared 3 of the last 7 days."` — the
    /// interference card's headline, from the app's own day counts.
    ///
    /// The no-overlap case is a finding of its own and is stated as one: the
    /// card exists because both domains are in the week, and that they never
    /// met is what the model is reasoning about.
    static func interferenceHeadline(_ metrics: InterferenceMetrics) -> String {
        guard metrics.overlapDays > 0 else {
            return "Strength and endurance never shared a day in the last \(metrics.days)."
        }
        return "Strength and endurance shared \(metrics.overlapDays) of the last \(metrics.days) days."
    }

    /// The card's three cells: strength days, endurance days, days carrying
    /// both.
    ///
    /// Always all three, where the recovery card leaves a cell out (US-15
    /// AC7). The difference is what a zero means: a week with no RPE recorded
    /// nothing, while "no day carried both" is a count the app made and the
    /// finding the card may be about.
    static func interferenceCells(_ metrics: InterferenceMetrics) -> [RecoveryMetricCell] {
        [
            RecoveryMetricCell(label: "Strength / \(metrics.days)d", value: "\(metrics.strengthDays)"),
            RecoveryMetricCell(label: "Cardio / \(metrics.days)d", value: "\(metrics.cardioDays)"),
            RecoveryMetricCell(label: "Both", value: "\(metrics.overlapDays)")
        ]
    }

    /// `value` with between `decimals` fraction digits, in `locale`. Callers
    /// round first, so Foundation's own rounding never decides a digit.
    private static func number(_ value: Double, decimals: ClosedRange<Int>, locale: Locale) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
    }
}

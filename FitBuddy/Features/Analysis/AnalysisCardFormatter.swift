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
    static func weight(_ kilograms: Double) -> String {
        kilograms.formatted(.number.precision(.fractionLength(0...2))) + " kg"
    }

    /// The signed step from `fromKg` to `toKg`: `"+2.5 kg"`, `"−1.25 kg"`.
    ///
    /// The difference is rounded to the displayed precision first, so floating
    /// point noise (`62.5 - 60.1`) cannot print as `2.4` next to weights that
    /// read `60.1` and `62.5`.
    static func delta(fromKg: Double, toKg: Double) -> String {
        let step = PlainWeightFormatter.rounded(toKg - fromKg)
        let magnitude = abs(step).formatted(.number.precision(.fractionLength(0...2)))
        let sign = step < 0 ? "\u{2212}" : "+"
        return "\(sign)\(magnitude) kg"
    }

    /// A per-week frequency as the imbalance card labels it: `"3×/wk"`,
    /// `"0.8×/wk"`. The figure is written exactly as the prompt stated it
    /// (`MuscleGroupFrequency`), so the card and the model's reasoning never
    /// disagree about the number.
    static func perWeek(_ perWeek: Double) -> String {
        "\(MuscleGroupFrequency.string(perWeek))×/wk"
    }

    /// `"Chest vs Legs"` — the imbalance card's header.
    static func imbalanceTitle(_ bars: [ImbalanceBar]) -> String {
        bars.map(\.group.displayName).joined(separator: " vs ")
    }

    /// `"You're training chest 3×/week but legs only 1×/week."` — the
    /// imbalance card's headline, built from the app's figures, never the
    /// model's. Expects the bars as `ImbalanceBar.bars` orders them, the more
    /// frequent group first.
    static func imbalanceHeadline(_ bars: [ImbalanceBar]) -> String {
        guard bars.count == 2 else { return imbalanceTitle(bars) }
        let high = bars[0]
        let low = bars[1]
        return """
        You're training \(high.group.displayName.lowercased()) \
        \(MuscleGroupFrequency.string(high.perWeek))×/week but \
        \(low.group.displayName.lowercased()) only \
        \(MuscleGroupFrequency.string(low.perWeek))×/week.
        """
    }

    /// `"You trained 6 of the last 7 days."` — the recovery card's headline,
    /// from the app's own count (US-3 AC6).
    static func recoveryHeadline(_ metrics: RecoveryMetrics) -> String {
        "You trained \(metrics.trainingDays) of the last 7 days."
    }

    /// `8.25` → `"8.3"`: one decimal, as the design shows it.
    static func rpe(_ rpe: Double) -> String {
        rpe.formatted(.number.precision(.fractionLength(1)))
    }

    /// `48` → `"48 h"`.
    static func rest(hours: Int) -> String {
        "\(hours) h"
    }
}

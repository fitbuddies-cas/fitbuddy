import Foundation

/// One figure in the recovery card's metrics row (US-14 AC4, US-15 AC7,
/// #177, #184).
struct RecoveryMetricCell: Equatable, Sendable {
    let label: String
    let value: String
    /// Rendered next to the value in `FBStat`'s smaller unit type, where a
    /// cell has one (#184).
    ///
    /// Only the heart rate does. "148 bpm" as one bold value wraps in a
    /// four-column row and makes the card 25 pt taller than a three-column
    /// one; as a value and a unit it fits, and it is what `FBStat` is built
    /// for. "48 h" stays one string: it has always been one, it fits, and
    /// splitting it would change a figure this change has no business
    /// touching.
    var unit: String?

    /// The row for `metrics`: sessions, average RPE, average heart rate,
    /// suggested rest — the last labelled "Rest" where all four are shown and
    /// "Suggested rest" otherwise.
    ///
    /// Only two cells are fixed — the session count, which since #184 covers
    /// strength and endurance together, and the suggested rest. A mean nobody
    /// recorded is left out rather than shown as `"—"` (US-15 AC7): Hevy sets
    /// carry no RPE unless the user logs one, a strength session has no heart
    /// rate at all, and a placeholder in a row of measurements reads like a
    /// measurement too.
    ///
    /// So a Hevy week with RPE keeps exactly the three cells of design 3.5, a
    /// Strava-only week reads sessions / heart rate / rest, and only a mixed
    /// week that recorded both means shows four.
    static func cells(for metrics: RecoveryMetrics) -> [RecoveryMetricCell] {
        var cells = [RecoveryMetricCell(label: "Sessions / 7d", value: "\(metrics.sessions)")]
        if let averageRPE = metrics.averageRPE {
            cells.append(RecoveryMetricCell(label: "Avg RPE", value: AnalysisCardFormatter.rpe(averageRPE)))
        }
        if let averageHeartRate = metrics.averageHeartRate {
            cells.append(
                RecoveryMetricCell(
                    label: "Avg HR",
                    value: HeartRateFormatter.value(Double(averageHeartRate)),
                    unit: HeartRateFormatter.unit
                )
            )
        }
        // "SUGGESTED REST" needs about 106 pt and scales to 84.8 pt at most,
        // while a four-column row gives each cell about 69.5 pt on a 390 pt
        // screen — so at four cells the label truncates rather than shrinks,
        // and truncation is invisible to a height assertion. The short form is
        // used only where the long one does not fit.
        cells.append(
            RecoveryMetricCell(
                label: cells.count == 3 ? "Rest" : "Suggested rest",
                value: AnalysisCardFormatter.rest(hours: metrics.suggestedRestHours)
            )
        )
        return cells
    }
}

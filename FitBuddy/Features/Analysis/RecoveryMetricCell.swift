import Foundation

/// One figure in the recovery card's metrics row (US-14 AC4, #177).
struct RecoveryMetricCell: Equatable, Sendable {
    let label: String
    let value: String

    /// The row for `metrics`: sessions, average RPE, suggested rest.
    ///
    /// Without an RPE the cell is left out rather than shown as `"—"`: Hevy
    /// sets carry no RPE unless the user logs one, and a placeholder in a row
    /// of measurements reads like a measurement too.
    static func cells(for metrics: RecoveryMetrics) -> [RecoveryMetricCell] {
        var cells = [RecoveryMetricCell(label: "Sessions / 7d", value: "\(metrics.sessions)")]
        if let averageRPE = metrics.averageRPE {
            cells.append(RecoveryMetricCell(label: "Avg RPE", value: AnalysisCardFormatter.rpe(averageRPE)))
        }
        cells.append(
            RecoveryMetricCell(
                label: "Suggested rest",
                value: AnalysisCardFormatter.rest(hours: metrics.suggestedRestHours)
            )
        )
        return cells
    }
}

import Foundation

/// The model's figure next to the one the app checked it against (#228):
/// "proposed 66 kg, working weight 60 kg, allowed 62.5–65 kg".
///
/// Only numbers — no exercise title, no reasoning, no session data. The
/// figure is what tells a too-bold step from a misquoted starting weight,
/// which the reason alone already names; the title would add who trained
/// what, which the measurement does not need.
struct AnalysisInterventionFigure: Codable, Equatable, Sendable {
    /// What the model wrote.
    let proposed: Double
    /// The app's own figure the proposal was checked against — the working
    /// weight, the listed reps, the week's metric. `nil` where the app had
    /// none, e.g. an exercise the prompt did not list.
    let app: Double?
    /// The lowest figure the app would have accepted, where the check is a
    /// range.
    let allowedMin: Double?
    /// The highest figure the app would have accepted, where the check is a
    /// range.
    let allowedMax: Double?
    let unit: AnalysisFigureUnit

    init(
        proposed: Double,
        app: Double? = nil,
        allowed: ClosedRange<Double>? = nil,
        unit: AnalysisFigureUnit
    ) {
        self.proposed = proposed
        self.app = app
        self.allowedMin = allowed?.lowerBound
        self.allowedMax = allowed?.upperBound
        self.unit = unit
    }
}

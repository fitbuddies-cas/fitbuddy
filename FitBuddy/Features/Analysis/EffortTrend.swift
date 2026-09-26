import Foundation

/// The direction one effort scale moved in, against itself (ADR-014 §3.4).
enum EffortTrend: String, Codable, Sendable {
    /// The last seven days' mean is above `AnalysisVerdictRule.effortRisingRatio`
    /// of the preceding weeks' mean.
    case rising
    /// Between the two ratios.
    case stable
    /// Below `AnalysisVerdictRule.effortFallingRatio`.
    case falling
}

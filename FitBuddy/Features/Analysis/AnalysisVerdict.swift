import Foundation

/// The one-word call an analysis makes about the next training block (US-14
/// AC1, #174). Drives the headline the result screen shows.
enum AnalysisVerdict: String, Codable, CaseIterable, Equatable, Sendable {
    /// The data supports adding load or reps.
    case progress
    /// Rest comes before any progression.
    case recover
    /// Neither progression nor extra rest is justified yet — keep training as
    /// is. Not in the design mock; #177 decides how it is shown.
    case hold
}

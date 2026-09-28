import Foundation

/// What the validator did to the part of the answer it intervened in (#228).
enum AnalysisInterventionAction: String, Codable, CaseIterable, Equatable, Sendable {
    /// A card the cache did not back became a note with the model's text.
    case downgraded
    /// A card left the report: no text to keep, or past `maxCards`.
    case dropped
    /// The app added a card the model left out — the recovery hint.
    case inserted
    /// The app put its own text or verdict in place of the model's.
    case replaced
}

import Foundation

/// The one-word call an analysis makes about the next training block (US-14
/// AC1, #174). Drives the headline the result screen shows.
///
/// Since #227 the app derives it from its own figures instead of taking the
/// model's — see `AnalysisVerdictRule` and ADR-014.
enum AnalysisVerdict: String, Codable, CaseIterable, Equatable, Sendable {
    /// The data supports adding load or reps.
    case progress
    /// Rest comes before any progression.
    case recover
    /// Neither progression nor extra rest is justified yet — keep training as
    /// is. Not in the design mock; #177 decides how it is shown.
    case hold
    /// No verdict at all: the app's own figures carry neither a step up nor a
    /// case for rest (US-16 AC6, ADR-014 §1). The recommendation is to keep
    /// training as before.
    ///
    /// Not a weaker `hold`. `hold` says "the data does not carry a step up",
    /// this says "the data carries nothing" — which is why the screen names
    /// the condition that produced it instead of guessing a card.
    case insufficientData

    /// The verdicts the model may choose from (ADR-014 §7).
    ///
    /// `insufficientData` is deliberately absent: it is a statement the app
    /// makes about its own data basis, not one a model can make about itself.
    /// `allCases` must therefore not be used to build the response schema.
    static let modelChoices: [AnalysisVerdict] = [.progress, .recover, .hold]
}

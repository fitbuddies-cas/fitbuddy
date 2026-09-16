import Foundation

/// The structured answer of an analysis run: a verdict, the cards the result
/// screen renders, and the same recommendation as prose (US-14, #174).
///
/// Decoded from the JSON every provider is asked for under
/// `AnalysisReportSchema`. Only the shape is checked here — whether a card's
/// exercise and starting weight match the cache is `AnalysisReportValidator`'s
/// job (#175).
struct AnalysisReport: Codable, Equatable, Sendable {
    /// One short sentence stating the verdict.
    let headline: String
    let verdict: AnalysisVerdict
    /// The recommendation cards, most important first. The prompt asks for one
    /// to four; the count is not enforced by the schema.
    let cards: [AnalysisCard]
    /// The whole recommendation as prose under 200 words. What the screen
    /// falls back to when the cards cannot be shown (US-14 AC5).
    let summary: String
}

import Foundation

/// An `AnalysisReport` after `AnalysisReportValidator` has checked every card
/// against the cache (US-14 AC3/AC4, #175) — what the result screen renders
/// (#177) and the history persists (#176).
///
/// Headline, verdict and summary are the model's, unchanged. The cards are
/// not: a card whose figures the cache does not confirm is a `.note`, and a
/// week that calls for recovery always carries a recovery card.
struct ValidatedAnalysisReport: Codable, Equatable, Sendable {
    let headline: String
    let verdict: AnalysisVerdict
    let cards: [AnalysisReportCard]
    let summary: String
}

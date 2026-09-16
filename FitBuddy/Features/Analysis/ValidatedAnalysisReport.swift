import Foundation

/// An `AnalysisReport` after `AnalysisReportValidator` has checked every card
/// against the cache (US-14 AC3/AC4, #175) — what the result screen renders
/// (#177) and the history persists (#176).
///
/// Lead and summary are the model's, unchanged, and so are headline and
/// verdict unless the recovery hint overrides them. The cards are not: a card
/// whose figures the cache does not confirm is a `.note`, and a week that
/// calls for recovery always carries a recovery card. A report without cards
/// is valid — thin data has a lead and a summary, no filler cards (#170).
struct ValidatedAnalysisReport: Codable, Equatable, Sendable {
    let headline: String
    let verdict: AnalysisVerdict
    /// The key takeaway in one to three sentences (#170).
    let lead: String
    let cards: [AnalysisReportCard]
    let summary: String
}

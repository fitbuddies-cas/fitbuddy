import Foundation

/// The structured answer of an analysis run: a verdict, a short lead, the
/// cards the result screen renders, and the whole recommendation as prose
/// (US-14, #174, #170).
///
/// Decoded from the JSON every provider is asked for under
/// `AnalysisReportSchema`. Only the shape is checked here — whether a card's
/// exercise and starting weight match the cache is `AnalysisReportValidator`'s
/// job (#175).
struct AnalysisReport: Codable, Equatable, Sendable {
    /// One short sentence stating the verdict.
    let headline: String
    let verdict: AnalysisVerdict
    /// The key takeaway in one to three sentences, readable on its own. Shown
    /// between the headline and the cards.
    let lead: String
    /// The recommendation cards, most important first. The prompt asks for
    /// zero to four; the count is not enforced by the schema.
    let cards: [AnalysisCard]
    /// The whole recommendation as prose under 200 words — the full analysis
    /// behind "Show full analysis", and what the screen falls back to when the
    /// cards cannot be shown (US-14 AC5).
    let summary: String

    enum CodingKeys: String, CodingKey {
        case headline, verdict, lead, cards, summary
    }
}

extension AnalysisReport {
    /// Decodes a report whose `lead` may be missing: an answer written without
    /// the schema can leave it out, and a report without cards or a lead is
    /// still a report. `AnalysisReportParser` derives a blank lead from the
    /// summary. Declared in an extension so the memberwise initialiser stays.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            headline: try container.decode(String.self, forKey: .headline),
            verdict: try container.decode(AnalysisVerdict.self, forKey: .verdict),
            lead: try container.decodeIfPresent(String.self, forKey: .lead) ?? "",
            cards: try container.decode([AnalysisCard].self, forKey: .cards),
            summary: try container.decode(String.self, forKey: .summary)
        )
    }
}

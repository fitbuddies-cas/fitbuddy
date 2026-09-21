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
            verdict: Self.offered(try container.decode(AnalysisVerdict.self, forKey: .verdict)),
            lead: try container.decodeIfPresent(String.self, forKey: .lead) ?? "",
            cards: try container.decode([AnalysisCard].self, forKey: .cards),
            summary: try container.decode(String.self, forKey: .summary)
        )
    }

    /// `verdict` if the model was allowed to send it, `hold` otherwise
    /// (ADR-013 §7).
    ///
    /// The schema offers `AnalysisVerdict.modelChoices`, but the schema is a
    /// request, not a guarantee: a provider without strict structured output,
    /// or a fallback path that parses prose, can still put `insufficientData`
    /// on the wire. Left alone it would do two kinds of damage — the app's
    /// verdict would equal the model's, so the app text ADR-013 §6 requires
    /// under "Not enough data to judge." would not be substituted, and the
    /// hit rate #228 and #229 measure would record a choice the model was
    /// never given.
    ///
    /// `hold` is the substitute because it is the one of the three offered
    /// verdicts closest to what such an answer meant. This is not the app's
    /// fourth class arriving by another route: that one is only ever set by
    /// `AnalysisVerdictRule`.
    static func offered(_ verdict: AnalysisVerdict) -> AnalysisVerdict {
        AnalysisVerdict.modelChoices.contains(verdict) ? verdict : .hold
    }
}
